#ifndef SEVRA_JS_H
#define SEVRA_JS_H
#include <stddef.h>
typedef struct SevraJS SevraJS;
SevraJS *sevra_js_create(void);
void sevra_js_destroy(SevraJS *engine);
// Result is JSON returned by the evaluated expression; failure text is prefixed with !.
char *sevra_js_eval(SevraJS *engine, const char *source, size_t length, int milliseconds);
void sevra_js_free(char *text);
#endif
