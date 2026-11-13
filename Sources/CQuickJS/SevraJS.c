#include "include/SevraJS.h"
#include "quickjs.h"
#include <stdlib.h>
#include <string.h>
#include <time.h>
struct SevraJS {
  JSRuntime *runtime; JSContext *context; double deadline;
  JSValue promises[64], reasons[64]; int rejection_count, rejection_overflow;
};
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static int interrupt(JSRuntime *rt, void *opaque) { (void)rt; return now() > ((SevraJS *)opaque)->deadline; }
static void rejection(JSContext *ctx, JSValueConst promise, JSValueConst reason, JS_BOOL handled, void *opaque) {
  SevraJS *e = opaque;
  if (handled) {
    for (int i = 0; i < e->rejection_count; i++) {
      if (JS_VALUE_GET_PTR(e->promises[i]) != JS_VALUE_GET_PTR(promise)) continue;
      JS_FreeValue(ctx, e->promises[i]); JS_FreeValue(ctx, e->reasons[i]);
      e->rejection_count--;
      e->promises[i] = e->promises[e->rejection_count];
      e->reasons[i] = e->reasons[e->rejection_count];
      return;
    }
  } else if (e->rejection_count < 64) {
    e->promises[e->rejection_count] = JS_DupValue(ctx, promise);
    e->reasons[e->rejection_count++] = JS_DupValue(ctx, reason);
  } else e->rejection_overflow = 1;
}
SevraJS *sevra_js_create(void) {
  SevraJS *e = calloc(1, sizeof(*e)); if (!e) return NULL;
  e->runtime = JS_NewRuntime(); if (!e->runtime) { free(e); return NULL; }
  JS_SetMemoryLimit(e->runtime, 64 * 1024 * 1024);
  JS_SetMaxStackSize(e->runtime, 512 * 1024);
  JS_SetInterruptHandler(e->runtime, interrupt, e);
  e->context = JS_NewContext(e->runtime);
  if (!e->context) { JS_FreeRuntime(e->runtime); free(e); return NULL; }
  JS_SetHostPromiseRejectionTracker(e->runtime, rejection, e);
  // No libc, OS, module loader, native callbacks, files or network are installed.
  return e;
}
void sevra_js_destroy(SevraJS *e) {
  if (!e) return;
  JS_SetHostPromiseRejectionTracker(e->runtime, NULL, NULL);
  for (int i = 0; i < e->rejection_count; i++) {
    JS_FreeValue(e->context, e->promises[i]); JS_FreeValue(e->context, e->reasons[i]);
  }
  JS_FreeContext(e->context); JS_FreeRuntime(e->runtime); free(e);
}
static char *failure(SevraJS *e) {
  JSValue exception = JS_GetException(e->context);
  const char *text = JS_ToCString(e->context, exception);
  const char *message = text ? text : "JavaScript execution or memory limit exceeded";
  JSValue stack = JS_IsError(e->context, exception) ? JS_GetPropertyStr(e->context, exception, "stack") : JS_UNDEFINED;
  const char *trace = JS_IsString(stack) ? JS_ToCString(e->context, stack) : NULL;
  size_t n = strnlen(message, 4096), k = trace ? strnlen(trace, 1536) : 0;
  char *out = malloc(n + k + 3);
  if (out) {
    out[0] = '!'; memcpy(out + 1, message, n);
    if (k) { out[n+1] = '\n'; memcpy(out + n + 2, trace, k); }
    out[n + 1 + (k ? k + 1 : 0)] = 0;
  }
  if (trace) JS_FreeCString(e->context, trace);
  JS_FreeValue(e->context, stack);
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
  if (e->rejection_overflow) return strdup("!Unhandled promise rejection limit exceeded");
  if (e->rejection_count) {
    JS_Throw(e->context, JS_DupValue(e->context, e->reasons[0]));
    return failure(e);
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
