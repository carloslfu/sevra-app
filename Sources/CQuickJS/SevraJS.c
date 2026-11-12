#include "include/SevraJS.h"
#include "quickjs.h"
#include <stdlib.h>
#include <string.h>
#include <time.h>
struct SevraJS { JSRuntime *runtime; JSContext *context; double deadline; };
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static int interrupt(JSRuntime *rt, void *opaque) { (void)rt; return now() > ((SevraJS *)opaque)->deadline; }
SevraJS *sevra_js_create(void) {
  SevraJS *e = calloc(1, sizeof(*e)); if (!e) return NULL;
  e->runtime = JS_NewRuntime(); if (!e->runtime) { free(e); return NULL; }
  JS_SetMemoryLimit(e->runtime, 64 * 1024 * 1024);
  JS_SetMaxStackSize(e->runtime, 512 * 1024);
  JS_SetInterruptHandler(e->runtime, interrupt, e);
  e->context = JS_NewContext(e->runtime);
  if (!e->context) { JS_FreeRuntime(e->runtime); free(e); return NULL; }
  // No libc, OS, module loader, native callbacks, files or network are installed.
  return e;
}
void sevra_js_destroy(SevraJS *e) { if (e) { JS_FreeContext(e->context); JS_FreeRuntime(e->runtime); free(e); } }
static char *failure(SevraJS *e) {
  JSValue exception = JS_GetException(e->context);
  const char *text = JS_ToCString(e->context, exception);
  const char *message = text ? text : "JavaScript execution or memory limit exceeded";
  size_t n = strnlen(message, 4096); char *out = malloc(n + 2);
  if (out) { out[0] = '!'; memcpy(out + 1, message, n); out[n+1] = 0; }
  if (text) JS_FreeCString(e->context, text);
  JS_FreeValue(e->context, exception); return out;
}
char *sevra_js_eval(SevraJS *e, const char *source, size_t length, int milliseconds) {
  e->deadline = now() + milliseconds / 1000.0;
  JS_UpdateStackTop(e->runtime);
  JSValue value = JS_Eval(e->context, source, length, "sevra-app.js", JS_EVAL_TYPE_GLOBAL);
  if (JS_IsException(value)) return failure(e);
  JS_FreeValue(e->context, value);
  JSContext *ctx = NULL; int jobs = 0;
  while (JS_IsJobPending(e->runtime)) {
    if (++jobs > 10000 || now() > e->deadline) return strdup("!JavaScript job budget exceeded");
    if (JS_ExecutePendingJob(e->runtime, &ctx) < 0) return failure(e);
  }
  const char *flush = "JSON.stringify(Sevra.__flush())";
  value = JS_Eval(e->context, flush, strlen(flush), "sevra-flush.js", JS_EVAL_TYPE_GLOBAL);
  if (JS_IsException(value)) return failure(e);
  size_t size = 0; const char *text = JS_ToCStringLen(e->context, &size, value);
  char *out = NULL;
  if (text && size <= 2 * 1024 * 1024) out = strndup(text, size);
  else out = strdup("!JavaScript output exceeds 2 MiB");
  if (text) JS_FreeCString(e->context, text); JS_FreeValue(e->context, value); return out;
}
void sevra_js_free(char *text) { free(text); }
