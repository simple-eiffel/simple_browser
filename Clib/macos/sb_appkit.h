/* sb_appkit.h - simple_browser's AppKit engine (WKWebView), docs/SIMPLE_BROWSER_SPEC.md section 2.

   Every entry point runs on the main thread. The C side never calls Eiffel: it queues events,
   and the Eiffel loop takes them with `sb_next' (section 4.1). Engines are small integers
   (1..SB_MAX_ENGINES); 0 is "none". */
#ifndef SB_APPKIT_H
#define SB_APPKIT_H

#define SB_MAX_ENGINES 32

/* Event kinds (section 4.1) */
#define SB_EVENT_CALL 1          /* text 1 name, 2 seq, 3 args JSON */
#define SB_EVENT_EVALUATED 2     /* a ticket, b status; text 1 JSON */
#define SB_EVENT_NAVIGATING 3    /* a decision, b kind, c main frame; text 1 url */
#define SB_EVENT_NEW_WINDOW 4    /* text 1 url */
#define SB_EVENT_TITLE 5         /* text 1 title */
#define SB_EVENT_LOADED 6        /* a status; text 1 error */
#define SB_EVENT_CLOSED 7

/* Size hints, as webview's: 0 none, 1 min, 2 max, 3 fixed */

int sb_is_gui_thread(void);

/* An engine: its own window (`a_parent' NULL), or a web view filling `a_parent' (an NSView *, or an
   NSWindow *: its content view). Ephemeral: an in-memory data store. Debug: the inspector. */
int sb_create(void *a_parent, int a_ephemeral, int a_debug);
void sb_destroy(int e);
void *sb_window(int e);

void sb_set_title(int e, const char *a_title);
void sb_set_size(int e, int a_width, int a_height, int a_hint);
void sb_show(int e);

void sb_navigate(int e, const char *a_url);
void sb_set_html(int e, const char *a_html, const char *a_base_url);   /* base NULL or "": none */

void sb_eval(int e, const char *a_script);              /* fire and forget */
void sb_add_script(int e, const char *a_script);        /* at document start, main frame, every load */
void sb_set_bridge(int e, const char *a_script);        /* the shared bridge script, first of all */
void sb_bind(int e, const char *a_name, const char *a_script);   /* a binding's own script */
void sb_unbind(int e, const char *a_name);
void sb_answer(int e, const char *a_seq, int a_status, const char *a_json);
void sb_evaluate(int e, int a_ticket, const char *a_body);   /* a function body that returns a string */

void sb_set_deciding(int e, int a_on);
void sb_decide(int e, int a_decision, int a_allow);

/* The loop: handle events for up to `a_ms' milliseconds, or until one is queued (1 if one waits).
   `sb_next' takes the oldest; its texts stay readable through `sb_text' until the next `sb_next'. */
int sb_pump(int a_ms);
int sb_next(int *a_kind, int *an_engine, int *a, int *b, int *c);
const char *sb_text(int i);
int sb_text_length(int i);
void sb_terminate(int e);   /* queues `closed' for `e' (the loop ends), the window stays until destroyed */

/* Tests */
int sb_test_window_count(void);
int sb_test_content_width(int e);
int sb_test_content_height(int e);
int sb_test_is_resizable(int e);

#endif
