/*
 * sb_win.h - the Windows engine of simple_browser: webview.dll, with WebView2 reached through
 * webview_get_native_handle for everything webview.dll does not offer.
 *
 * The rules (SIMPLE_BROWSER_SPEC.md, section 4):
 *   - C never calls Eiffel. Every WebView2 callback pushes an event on one process-wide queue,
 *     keyed by engine id; Eiffel takes them with sbw_take after sbw_pump returns.
 *   - sbw_pump is called from a `blocking' external: while it runs, this thread is outside
 *     Eiffel code and other processors' garbage collections do not wait for it. Nothing here
 *     touches an Eiffel object.
 *   - Inline C: this header is compiled into every C file whose class has an external that uses
 *     it, so its mutable data is SBW_SHARED (__declspec(selectany) for MSVC,
 *     __attribute__((weak)) for GCC and Clang): one copy for the whole program, not one per
 *     translation unit. Functions are static; they reach only the shared data.
 *   - The COM event handlers are C objects with hand-built vtables (WebView2.h's C interface).
 *
 * Event kinds (BROWSER_ENGINE): 1 call, 2 evaluated, 3 navigating, 4 new_window,
 * 5 title_changed, 6 loaded, 7 closed. Kind 100 is a raw web message, which WEBVIEW_ENGINE
 * turns into a call or an evaluated event (or a navigation-kind hint) in Eiffel.
 *
 * Copyright (c) 2025-2026 Larry Rix
 */

#ifndef SB_WIN_H
#define SB_WIN_H

#ifndef COBJMACROS
#define COBJMACROS
#endif

#include <windows.h>
#include <objbase.h>
#include <shlwapi.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "WebView2.h"
#include "api.h"

#if defined(_MSC_VER)
#define SBW_SHARED __declspec(selectany)
#else
#define SBW_SHARED __attribute__((weak))
#endif

#define SBW_MAX_ENGINES 16
#define SBW_MAX_HELD 64
#define SBW_MAX_SCRIPTS 64
#define SBW_NAME_MAX 128
#define SBW_MAX_FRAMES 64

#define SBW_EVENT_CALL 1
#define SBW_EVENT_EVALUATED 2
#define SBW_EVENT_NAVIGATING 3
#define SBW_EVENT_NEW_WINDOW 4
#define SBW_EVENT_TITLE 5
#define SBW_EVENT_LOADED 6
#define SBW_EVENT_CLOSED 7
#define SBW_EVENT_MESSAGE 100

/* ------------------------------------------------------------------------------------------ */
/* Shared data                                                                                */
/* ------------------------------------------------------------------------------------------ */

typedef struct sbw_event_s {
    int engine;
    int kind;
    int a, b, c;
    char *text[3];
    struct sbw_event_s *next;
} sbw_event_t;

typedef struct {
    int in_use;
    char name[SBW_NAME_MAX];  /* the binding's name; empty for the bridge */
    wchar_t *id;              /* WebView2's script id, once the add has completed */
    int removed;              /* removed before the id arrived: remove it when it does */
} sbw_script_t;

typedef struct {
    int in_use;
    int disposing;
    webview_t w;
    HWND window;              /* the top-level window (own) or the parent (embedded) */
    int owns_window;
    WNDPROC old_proc;         /* the window procedure we subclassed (own window only) */
    int suppress_show;
    int closed;
    ICoreWebView2Controller *controller;  /* webview.dll's; not referenced by us */
    ICoreWebView2 *view;                  /* referenced by us */
    ICoreWebView2Environment *environment;/* referenced by us, or NULL */
    int deciding;
    int pass_pending;         /* program's own loads still to let through */
    UINT64 pass_navigation;   /* the navigation id let through, for its redirects */
    int pass_valid;
    int min_w, min_h, max_w, max_h, fixed;  /* size hints, logical pixels; 0 = none */
    wchar_t *served_url;      /* set_html, set_html_with_base: the URL answered with served_html */
    char *served_html;
    wchar_t *echo_url;        /* test hook: the URL answered with the request's method and body */
    int ephemeral;
    wchar_t data_folder[MAX_PATH];
    sbw_script_t scripts[SBW_MAX_SCRIPTS];
    sbw_event_t *current;     /* the event last taken */
} sbw_engine_t;

typedef struct {
    int in_use;
    int engine;
    int number;
    int frame;                /* 0 the main frame, else 1 + the iframe's slot in sbw_frames */
    wchar_t *url;             /* the navigation, canceled at once; replayed if Eiffel allows it */
} sbw_held_t;

/* An iframe of an engine's page (ICoreWebView2_4 FrameCreated), with its own navigations. */
typedef struct {
    int in_use;
    int engine;
    ICoreWebView2Frame2 *frame;  /* referenced by us */
    int started;              /* its first navigation (the iframe's own src) is let through */
    int pass_pending;         /* replays still to let through */
    UINT64 pass_navigation;
    int pass_valid;
} sbw_frame_t;

SBW_SHARED sbw_engine_t sbw_engines[SBW_MAX_ENGINES] = {0};
SBW_SHARED sbw_held_t sbw_held[SBW_MAX_HELD] = {0};
SBW_SHARED sbw_frame_t sbw_frames[SBW_MAX_FRAMES] = {0};
SBW_SHARED sbw_event_t *sbw_queue_head = NULL;
SBW_SHARED sbw_event_t *sbw_queue_tail = NULL;
SBW_SHARED SRWLOCK sbw_lock = SRWLOCK_INIT;
SBW_SHARED int sbw_next_decision = 0;
SBW_SHARED int sbw_last_error_code = 0;
SBW_SHARED int sbw_folder_serial = 0;

/* ------------------------------------------------------------------------------------------ */
/* Logging (off unless SB_WIN_LOG names a file)                                               */
/* ------------------------------------------------------------------------------------------ */

static void sbw_log (const char *a_format, ...) {
    char l_path[MAX_PATH];
    DWORD l_n = GetEnvironmentVariableA ("SB_WIN_LOG", l_path, MAX_PATH);
    if (l_n > 0 && l_n < MAX_PATH) {
        FILE *l_file = fopen (l_path, "a");
        if (l_file) {
            va_list l_args;
            va_start (l_args, a_format);
            fprintf (l_file, "[%lu] ", (unsigned long) GetTickCount ());
            vfprintf (l_file, a_format, l_args);
            fprintf (l_file, "\n");
            va_end (l_args);
            fclose (l_file);
        }
    }
}

/* ------------------------------------------------------------------------------------------ */
/* Text                                                                                       */
/* ------------------------------------------------------------------------------------------ */

static char *sbw_utf8 (LPCWSTR a_wide) {
    int l_n;
    char *l_result;
    if (!a_wide) { a_wide = L""; }
    l_n = WideCharToMultiByte (CP_UTF8, 0, a_wide, -1, NULL, 0, NULL, NULL);
    if (l_n <= 0) { l_n = 1; }
    l_result = (char *) malloc ((size_t) l_n);
    if (l_result) {
        l_result[0] = '\0';
        WideCharToMultiByte (CP_UTF8, 0, a_wide, -1, l_result, l_n, NULL, NULL);
    }
    return l_result;
}

static wchar_t *sbw_wide (const char *a_utf8) {
    int l_n;
    wchar_t *l_result;
    if (!a_utf8) { a_utf8 = ""; }
    l_n = MultiByteToWideChar (CP_UTF8, 0, a_utf8, -1, NULL, 0);
    if (l_n <= 0) { l_n = 1; }
    l_result = (wchar_t *) malloc (sizeof (wchar_t) * (size_t) l_n);
    if (l_result) {
        l_result[0] = L'\0';
        MultiByteToWideChar (CP_UTF8, 0, a_utf8, -1, l_result, l_n);
    }
    return l_result;
}

static char *sbw_copy (const char *a_text) {
    size_t l_n;
    char *l_result;
    if (!a_text) { return NULL; }
    l_n = strlen (a_text) + 1;
    l_result = (char *) malloc (l_n);
    if (l_result) { memcpy (l_result, a_text, l_n); }
    return l_result;
}

/* ------------------------------------------------------------------------------------------ */
/* Engines and the queue                                                                      */
/* ------------------------------------------------------------------------------------------ */

static sbw_engine_t *sbw_engine (int a_id) {
    if (a_id >= 1 && a_id <= SBW_MAX_ENGINES && sbw_engines[a_id - 1].in_use) {
        return &sbw_engines[a_id - 1];
    }
    return NULL;
}

static sbw_engine_t *sbw_engine_for_window (HWND a_window) {
    int i;
    for (i = 0; i < SBW_MAX_ENGINES; i++) {
        if (sbw_engines[i].in_use && sbw_engines[i].owns_window && sbw_engines[i].window == a_window) {
            return &sbw_engines[i];
        }
    }
    return NULL;
}

static void sbw_free_event (sbw_event_t *a_event) {
    int i;
    if (a_event) {
        for (i = 0; i < 3; i++) { free (a_event->text[i]); }
        free (a_event);
    }
}

/* Queue an event for engine `a_id'; the texts are copied. */
static void sbw_push (int a_id, int a_kind, int a_a, int a_b, int a_c,
                      const char *a_t1, const char *a_t2, const char *a_t3) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    sbw_event_t *l_event;
    if (!l_engine || l_engine->disposing) { return; }
    l_event = (sbw_event_t *) calloc (1, sizeof (sbw_event_t));
    if (!l_event) { return; }
    l_event->engine = a_id;
    l_event->kind = a_kind;
    l_event->a = a_a;
    l_event->b = a_b;
    l_event->c = a_c;
    l_event->text[0] = sbw_copy (a_t1);
    l_event->text[1] = sbw_copy (a_t2);
    l_event->text[2] = sbw_copy (a_t3);
    AcquireSRWLockExclusive (&sbw_lock);
    if (sbw_queue_tail) { sbw_queue_tail->next = l_event; } else { sbw_queue_head = l_event; }
    sbw_queue_tail = l_event;
    ReleaseSRWLockExclusive (&sbw_lock);
    sbw_log ("push engine=%d kind=%d a=%d b=%d c=%d t1=%.200s", a_id, a_kind, a_a, a_b, a_c,
             a_t1 ? a_t1 : "");
}

static void sbw_push_wide (int a_id, int a_kind, int a_a, int a_b, int a_c, LPCWSTR a_text) {
    char *l_text = sbw_utf8 (a_text);
    sbw_push (a_id, a_kind, a_a, a_b, a_c, l_text, NULL, NULL);
    free (l_text);
}

/* Is an event queued for engine `a_id'? */
static int sbw_has_event (int a_id) {
    sbw_event_t *l_event;
    int l_result = 0;
    AcquireSRWLockShared (&sbw_lock);
    for (l_event = sbw_queue_head; l_event && !l_result; l_event = l_event->next) {
        if (l_event->engine == a_id) { l_result = 1; }
    }
    ReleaseSRWLockShared (&sbw_lock);
    return l_result;
}

/* Take the oldest event for engine `a_id' into its `current'; 0 if none. */
static int sbw_take (int a_id) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    sbw_event_t *l_event, *l_previous = NULL;
    if (!l_engine) { return 0; }
    sbw_free_event (l_engine->current);
    l_engine->current = NULL;
    AcquireSRWLockExclusive (&sbw_lock);
    for (l_event = sbw_queue_head; l_event; l_previous = l_event, l_event = l_event->next) {
        if (l_event->engine == a_id) {
            if (l_previous) { l_previous->next = l_event->next; } else { sbw_queue_head = l_event->next; }
            if (sbw_queue_tail == l_event) { sbw_queue_tail = l_previous; }
            l_event->next = NULL;
            l_engine->current = l_event;
            break;
        }
    }
    ReleaseSRWLockExclusive (&sbw_lock);
    return l_engine->current != NULL;
}

static int sbw_current_kind (int a_id) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    return (l_engine && l_engine->current) ? l_engine->current->kind : 0;
}

static int sbw_current_a (int a_id) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    return (l_engine && l_engine->current) ? l_engine->current->a : 0;
}

static int sbw_current_b (int a_id) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    return (l_engine && l_engine->current) ? l_engine->current->b : 0;
}

static int sbw_current_c (int a_id) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    return (l_engine && l_engine->current) ? l_engine->current->c : 0;
}

static const char *sbw_current_text (int a_id, int a_index) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    const char *l_result = NULL;
    if (l_engine && l_engine->current && a_index >= 1 && a_index <= 3) {
        l_result = l_engine->current->text[a_index - 1];
    }
    return l_result ? l_result : "";
}

/* Drop every queued event of engine `a_id'. */
static void sbw_drop_events (int a_id) {
    sbw_event_t *l_event, *l_previous = NULL, *l_next;
    AcquireSRWLockExclusive (&sbw_lock);
    for (l_event = sbw_queue_head; l_event; l_event = l_next) {
        l_next = l_event->next;
        if (l_event->engine == a_id) {
            if (l_previous) { l_previous->next = l_next; } else { sbw_queue_head = l_next; }
            if (sbw_queue_tail == l_event) { sbw_queue_tail = l_previous; }
            sbw_free_event (l_event);
        } else {
            l_previous = l_event;
        }
    }
    ReleaseSRWLockExclusive (&sbw_lock);
}

/* ------------------------------------------------------------------------------------------ */
/* COM handler objects                                                                        */
/* ------------------------------------------------------------------------------------------ */

typedef struct {
    void *vtbl;
    LONG refs;
    const IID *iid;
    int engine;
    int extra;  /* main frame flag, ticket, or script slot */
} sbw_handler_t;

static HRESULT sbw_handler_query (sbw_handler_t *a_self, REFIID a_iid, void **a_out) {
    if (!a_out) { return E_POINTER; }
    if (IsEqualIID (a_iid, &IID_IUnknown) || IsEqualIID (a_iid, a_self->iid)) {
        *a_out = a_self;
        InterlockedIncrement (&a_self->refs);
        return S_OK;
    }
    *a_out = NULL;
    return E_NOINTERFACE;
}

static ULONG sbw_handler_add_ref (sbw_handler_t *a_self) {
    return (ULONG) InterlockedIncrement (&a_self->refs);
}

static ULONG sbw_handler_release (sbw_handler_t *a_self) {
    LONG l_refs = InterlockedDecrement (&a_self->refs);
    if (l_refs == 0) { free (a_self); }
    return (ULONG) l_refs;
}

static sbw_handler_t *sbw_new_handler (void *a_vtbl, const IID *a_iid, int a_engine, int a_extra) {
    sbw_handler_t *l_result = (sbw_handler_t *) calloc (1, sizeof (sbw_handler_t));
    if (l_result) {
        l_result->vtbl = a_vtbl;
        l_result->refs = 1;
        l_result->iid = a_iid;
        l_result->engine = a_engine;
        l_result->extra = a_extra;
    }
    return l_result;
}

/* QueryInterface, AddRef and Release for handler interface T. */
#define SBW_HANDLER_UNKNOWN(T) \
    static HRESULT STDMETHODCALLTYPE T##_sbw_query (T *a_this, REFIID a_iid, void **a_out) { \
        return sbw_handler_query ((sbw_handler_t *) a_this, a_iid, a_out); } \
    static ULONG STDMETHODCALLTYPE T##_sbw_add_ref (T *a_this) { \
        return sbw_handler_add_ref ((sbw_handler_t *) a_this); } \
    static ULONG STDMETHODCALLTYPE T##_sbw_release (T *a_this) { \
        return sbw_handler_release ((sbw_handler_t *) a_this); }

/* --- WebMessageReceived: the bridge's channel ------------------------------------------- */

SBW_HANDLER_UNKNOWN (ICoreWebView2WebMessageReceivedEventHandler)

static HRESULT STDMETHODCALLTYPE sbw_on_message (ICoreWebView2WebMessageReceivedEventHandler *a_this,
        ICoreWebView2 *a_sender, ICoreWebView2WebMessageReceivedEventArgs *a_args) {
    sbw_handler_t *l_self = (sbw_handler_t *) a_this;
    LPWSTR l_json = NULL;
    if (SUCCEEDED (ICoreWebView2WebMessageReceivedEventArgs_get_WebMessageAsJson (a_args, &l_json)) && l_json) {
        sbw_push_wide (l_self->engine, SBW_EVENT_MESSAGE, 0, 0, 0, l_json);
        CoTaskMemFree (l_json);
    }
    return S_OK;
}

static ICoreWebView2WebMessageReceivedEventHandlerVtbl sbw_message_vtbl = {
    ICoreWebView2WebMessageReceivedEventHandler_sbw_query,
    ICoreWebView2WebMessageReceivedEventHandler_sbw_add_ref,
    ICoreWebView2WebMessageReceivedEventHandler_sbw_release,
    sbw_on_message
};

/* An iframe's web message: queued with c = 1 + the frame's slot. */
SBW_HANDLER_UNKNOWN (ICoreWebView2FrameWebMessageReceivedEventHandler)

static HRESULT STDMETHODCALLTYPE sbw_on_frame_message (ICoreWebView2FrameWebMessageReceivedEventHandler *a_this,
        ICoreWebView2Frame *a_sender, ICoreWebView2WebMessageReceivedEventArgs *a_args) {
    sbw_handler_t *l_self = (sbw_handler_t *) a_this;
    LPWSTR l_json = NULL;
    if (SUCCEEDED (ICoreWebView2WebMessageReceivedEventArgs_get_WebMessageAsJson (a_args, &l_json)) && l_json) {
        sbw_push_wide (l_self->engine, SBW_EVENT_MESSAGE, 0, 0, l_self->extra + 1, l_json);
        CoTaskMemFree (l_json);
    }
    return S_OK;
}

static ICoreWebView2FrameWebMessageReceivedEventHandlerVtbl sbw_frame_message_vtbl = {
    ICoreWebView2FrameWebMessageReceivedEventHandler_sbw_query,
    ICoreWebView2FrameWebMessageReceivedEventHandler_sbw_add_ref,
    ICoreWebView2FrameWebMessageReceivedEventHandler_sbw_release,
    sbw_on_frame_message
};

/* The iframe `a_frame' (1 + slot) of engine `a_id', if it is alive. */
static sbw_frame_t *sbw_frame (int a_id, int a_frame) {
    if (a_frame >= 1 && a_frame <= SBW_MAX_FRAMES && sbw_frames[a_frame - 1].in_use
            && sbw_frames[a_frame - 1].engine == a_id) {
        return &sbw_frames[a_frame - 1];
    }
    return NULL;
}

/* `a_text' as a JavaScript string literal, double-quoted (UTF-16). */
static wchar_t *sbw_js_string (LPCWSTR a_text) {
    size_t l_n = wcslen (a_text ? a_text : L"");
    wchar_t *l_result = (wchar_t *) malloc (sizeof (wchar_t) * (l_n * 6 + 3));
    size_t i, j = 0;
    if (!l_result) { return NULL; }
    l_result[j++] = L'"';
    for (i = 0; i < l_n; i++) {
        wchar_t l_c = a_text[i];
        if (l_c == L'"' || l_c == L'\\') {
            l_result[j++] = L'\\';
            l_result[j++] = l_c;
        } else if (l_c < 32 || l_c == 0x2028 || l_c == 0x2029) {
            j += (size_t) swprintf (l_result + j, 7, L"\\u%04x", (unsigned int) l_c);
        } else {
            l_result[j++] = l_c;
        }
    }
    l_result[j++] = L'"';
    l_result[j] = 0;
    return l_result;
}

/* --- NavigationStarting: decisions ------------------------------------------------------
   WebView2's NavigationStarting takes no deferral: the handler must say Cancel or not before it
   returns, and C never calls Eiffel. So a navigation the page starts is canceled at once and
   queued as `navigating'; if the Eiffel handler allows it, `sbw_decide' replays it with
   ICoreWebView2::Navigate, which the engine lets through as its own load. */

static int sbw_hold (int a_engine, int a_frame, LPCWSTR a_url) {
    int i;
    size_t l_n;
    for (i = 0; i < SBW_MAX_HELD; i++) {
        if (!sbw_held[i].in_use) {
            sbw_next_decision = sbw_next_decision + 1;
            if (sbw_next_decision <= 0) { sbw_next_decision = 1; }
            l_n = wcslen (a_url ? a_url : L"") + 1;
            sbw_held[i].url = (wchar_t *) malloc (sizeof (wchar_t) * l_n);
            if (!sbw_held[i].url) { return 0; }
            memcpy (sbw_held[i].url, a_url ? a_url : L"", sizeof (wchar_t) * l_n);
            sbw_held[i].in_use = 1;
            sbw_held[i].engine = a_engine;
            sbw_held[i].frame = a_frame;
            sbw_held[i].number = sbw_next_decision;
            return sbw_next_decision;
        }
    }
    return 0;
}

/* Answer held decision `a_number' of engine `a_engine': replay the navigation if allowed, in
   the main frame with ICoreWebView2::Navigate, in an iframe with location.assign there. */
static void sbw_answer_held (int a_engine, int a_number, int a_allow) {
    sbw_engine_t *l_engine = sbw_engine (a_engine);
    sbw_frame_t *l_frame;
    wchar_t *l_literal;
    wchar_t *l_script;
    size_t l_n;
    int i;
    for (i = 0; i < SBW_MAX_HELD; i++) {
        if (sbw_held[i].in_use && sbw_held[i].engine == a_engine && sbw_held[i].number == a_number) {
            sbw_held[i].in_use = 0;
            sbw_log ("decide engine=%d number=%d frame=%d allow=%d url=%.200S", a_engine, a_number,
                     sbw_held[i].frame, a_allow, sbw_held[i].url);
            if (a_allow && l_engine && !l_engine->disposing && l_engine->view) {
                if (sbw_held[i].frame == 0) {
                    l_engine->pass_pending = l_engine->pass_pending + 1;
                    ICoreWebView2_Navigate (l_engine->view, sbw_held[i].url);
                } else if ((l_frame = sbw_frame (a_engine, sbw_held[i].frame)) != NULL) {
                    l_literal = sbw_js_string (sbw_held[i].url);
                    if (l_literal) {
                        l_n = wcslen (l_literal) + 32;
                        l_script = (wchar_t *) malloc (sizeof (wchar_t) * l_n);
                        if (l_script) {
                            swprintf (l_script, l_n, L"location.assign (%ls);", l_literal);
                            l_frame->pass_pending = l_frame->pass_pending + 1;
                            ICoreWebView2Frame2_ExecuteScript (l_frame->frame, l_script, NULL);
                            free (l_script);
                        }
                        free (l_literal);
                    }
                }
            }
            free (sbw_held[i].url);
            sbw_held[i].url = NULL;
            break;
        }
    }
}

SBW_HANDLER_UNKNOWN (ICoreWebView2NavigationStartingEventHandler)

/* The decision rule for a navigation of engine `a_id' in frame `a_frame' (0 the main frame). */
static void sbw_navigation_starts (int a_id, int a_frame, ICoreWebView2NavigationStartingEventArgs *a_args) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    sbw_frame_t *l_frame = a_frame ? sbw_frame (a_id, a_frame) : NULL;
    UINT64 l_navigation = 0;
    BOOL l_user = FALSE, l_redirected = FALSE;
    LPWSTR l_uri = NULL;
    int l_number;
    char *l_text;
    int *l_pass_pending;
    UINT64 *l_pass_navigation;
    int *l_pass_valid;
    if (!l_engine || l_engine->disposing || (a_frame && !l_frame)) { return; }
    l_pass_pending = l_frame ? &l_frame->pass_pending : &l_engine->pass_pending;
    l_pass_navigation = l_frame ? &l_frame->pass_navigation : &l_engine->pass_navigation;
    l_pass_valid = l_frame ? &l_frame->pass_valid : &l_engine->pass_valid;
    ICoreWebView2NavigationStartingEventArgs_get_NavigationId (a_args, &l_navigation);
    ICoreWebView2NavigationStartingEventArgs_get_IsUserInitiated (a_args, &l_user);
    ICoreWebView2NavigationStartingEventArgs_get_IsRedirected (a_args, &l_redirected);
    ICoreWebView2NavigationStartingEventArgs_get_Uri (a_args, &l_uri);
    sbw_log ("navigation starting engine=%d frame=%d id=%llu user=%d redirected=%d pass=%d deciding=%d uri=%.200S",
             a_id, a_frame, (unsigned long long) l_navigation, (int) l_user,
             (int) l_redirected, *l_pass_pending, l_engine->deciding, l_uri ? l_uri : L"");
    if (l_frame && !l_frame->started) {
        /* An iframe's first navigation loads its own src (or srcdoc): part of the page's load,
           like the main frame's own load, and nothing a replay could reproduce. */
        l_frame->started = 1;
        *l_pass_navigation = l_navigation;
        *l_pass_valid = 1;
    } else if (*l_pass_pending > 0) {
        /* The program's own navigate or set_html, or a replay: never asked (spec 4.4). */
        *l_pass_pending = *l_pass_pending - 1;
        *l_pass_navigation = l_navigation;
        *l_pass_valid = 1;
    } else if (*l_pass_valid && l_navigation == *l_pass_navigation) {
        /* A redirect of a navigation already let through. */
    } else if (l_engine->deciding) {
        l_number = sbw_hold (a_id, a_frame, l_uri);
        if (l_number > 0) {
            ICoreWebView2NavigationStartingEventArgs_put_Cancel (a_args, TRUE);
            l_text = sbw_utf8 (l_uri);
            sbw_push (a_id, SBW_EVENT_NAVIGATING, l_number, 0, a_frame == 0, l_text, NULL, NULL);
            free (l_text);
        }
        /* No room to hold it: allowed, as with no handler. */
    }
    if (l_uri) { CoTaskMemFree (l_uri); }
}

static HRESULT STDMETHODCALLTYPE sbw_on_navigation_starting (ICoreWebView2NavigationStartingEventHandler *a_this,
        ICoreWebView2 *a_sender, ICoreWebView2NavigationStartingEventArgs *a_args) {
    sbw_navigation_starts (((sbw_handler_t *) a_this)->engine, 0, a_args);
    return S_OK;
}

static ICoreWebView2NavigationStartingEventHandlerVtbl sbw_navigation_starting_vtbl = {
    ICoreWebView2NavigationStartingEventHandler_sbw_query,
    ICoreWebView2NavigationStartingEventHandler_sbw_add_ref,
    ICoreWebView2NavigationStartingEventHandler_sbw_release,
    sbw_on_navigation_starting
};

SBW_HANDLER_UNKNOWN (ICoreWebView2FrameNavigationStartingEventHandler)

static HRESULT STDMETHODCALLTYPE sbw_on_frame_navigation_starting (ICoreWebView2FrameNavigationStartingEventHandler *a_this,
        ICoreWebView2Frame *a_sender, ICoreWebView2NavigationStartingEventArgs *a_args) {
    sbw_handler_t *l_self = (sbw_handler_t *) a_this;
    sbw_navigation_starts (l_self->engine, l_self->extra + 1, a_args);
    return S_OK;
}

static ICoreWebView2FrameNavigationStartingEventHandlerVtbl sbw_frame_navigation_starting_vtbl = {
    ICoreWebView2FrameNavigationStartingEventHandler_sbw_query,
    ICoreWebView2FrameNavigationStartingEventHandler_sbw_add_ref,
    ICoreWebView2FrameNavigationStartingEventHandler_sbw_release,
    sbw_on_frame_navigation_starting
};

/* --- FrameDestroyed and FrameCreated: the iframes of the page ----------------------------- */

static void sbw_release_frame (int a_slot) {
    if (a_slot >= 0 && a_slot < SBW_MAX_FRAMES && sbw_frames[a_slot].in_use) {
        sbw_frames[a_slot].in_use = 0;
        if (sbw_frames[a_slot].frame) { ICoreWebView2Frame2_Release (sbw_frames[a_slot].frame); }
        sbw_frames[a_slot].frame = NULL;
    }
}

SBW_HANDLER_UNKNOWN (ICoreWebView2FrameDestroyedEventHandler)

static HRESULT STDMETHODCALLTYPE sbw_on_frame_destroyed (ICoreWebView2FrameDestroyedEventHandler *a_this,
        ICoreWebView2Frame *a_sender, IUnknown *a_args) {
    sbw_handler_t *l_self = (sbw_handler_t *) a_this;
    if (sbw_frame (l_self->engine, l_self->extra + 1)) { sbw_release_frame (l_self->extra); }
    return S_OK;
}

static ICoreWebView2FrameDestroyedEventHandlerVtbl sbw_frame_destroyed_vtbl = {
    ICoreWebView2FrameDestroyedEventHandler_sbw_query,
    ICoreWebView2FrameDestroyedEventHandler_sbw_add_ref,
    ICoreWebView2FrameDestroyedEventHandler_sbw_release,
    sbw_on_frame_destroyed
};

SBW_HANDLER_UNKNOWN (ICoreWebView2FrameCreatedEventHandler)

static HRESULT STDMETHODCALLTYPE sbw_on_frame_created (ICoreWebView2FrameCreatedEventHandler *a_this,
        ICoreWebView2 *a_sender, ICoreWebView2FrameCreatedEventArgs *a_args) {
    sbw_handler_t *l_self = (sbw_handler_t *) a_this;
    sbw_engine_t *l_engine = sbw_engine (l_self->engine);
    ICoreWebView2Frame *l_frame = NULL;
    ICoreWebView2Frame2 *l_frame_2 = NULL;
    sbw_handler_t *l_handler;
    EventRegistrationToken l_token;
    int i, l_slot = -1;
    if (!l_engine || l_engine->disposing) { return S_OK; }
    if (FAILED (ICoreWebView2FrameCreatedEventArgs_get_Frame (a_args, &l_frame)) || !l_frame) { return S_OK; }
    if (SUCCEEDED (ICoreWebView2Frame_QueryInterface (l_frame, &IID_ICoreWebView2Frame2, (void **) &l_frame_2)) && l_frame_2) {
        for (i = 0; i < SBW_MAX_FRAMES && l_slot < 0; i++) {
            if (!sbw_frames[i].in_use) { l_slot = i; }
        }
        if (l_slot >= 0) {
            memset (&sbw_frames[l_slot], 0, sizeof (sbw_frame_t));
            sbw_frames[l_slot].in_use = 1;
            sbw_frames[l_slot].engine = l_self->engine;
            sbw_frames[l_slot].frame = l_frame_2;
            l_handler = sbw_new_handler (&sbw_frame_navigation_starting_vtbl,
                &IID_ICoreWebView2FrameNavigationStartingEventHandler, l_self->engine, l_slot);
            if (l_handler) {
                ICoreWebView2Frame2_add_NavigationStarting (l_frame_2,
                    (ICoreWebView2FrameNavigationStartingEventHandler *) l_handler, &l_token);
                sbw_handler_release (l_handler);
            }
            l_handler = sbw_new_handler (&sbw_frame_message_vtbl,
                &IID_ICoreWebView2FrameWebMessageReceivedEventHandler, l_self->engine, l_slot);
            if (l_handler) {
                ICoreWebView2Frame2_add_WebMessageReceived (l_frame_2,
                    (ICoreWebView2FrameWebMessageReceivedEventHandler *) l_handler, &l_token);
                sbw_handler_release (l_handler);
            }
            l_handler = sbw_new_handler (&sbw_frame_destroyed_vtbl,
                &IID_ICoreWebView2FrameDestroyedEventHandler, l_self->engine, l_slot);
            if (l_handler) {
                ICoreWebView2Frame2_add_Destroyed (l_frame_2,
                    (ICoreWebView2FrameDestroyedEventHandler *) l_handler, &l_token);
                sbw_handler_release (l_handler);
            }
            sbw_log ("frame created engine=%d slot=%d", l_self->engine, l_slot);
        } else {
            ICoreWebView2Frame2_Release (l_frame_2);
        }
    }
    ICoreWebView2Frame_Release (l_frame);
    return S_OK;
}

static ICoreWebView2FrameCreatedEventHandlerVtbl sbw_frame_created_vtbl = {
    ICoreWebView2FrameCreatedEventHandler_sbw_query,
    ICoreWebView2FrameCreatedEventHandler_sbw_add_ref,
    ICoreWebView2FrameCreatedEventHandler_sbw_release,
    sbw_on_frame_created
};

/* --- NewWindowRequested: reported, never opened ------------------------------------------- */

SBW_HANDLER_UNKNOWN (ICoreWebView2NewWindowRequestedEventHandler)

static HRESULT STDMETHODCALLTYPE sbw_on_new_window (ICoreWebView2NewWindowRequestedEventHandler *a_this,
        ICoreWebView2 *a_sender, ICoreWebView2NewWindowRequestedEventArgs *a_args) {
    sbw_handler_t *l_self = (sbw_handler_t *) a_this;
    LPWSTR l_uri = NULL;
    ICoreWebView2NewWindowRequestedEventArgs_put_Handled (a_args, TRUE);
    ICoreWebView2NewWindowRequestedEventArgs_get_Uri (a_args, &l_uri);
    sbw_push_wide (l_self->engine, SBW_EVENT_NEW_WINDOW, 0, 0, 0, l_uri);
    if (l_uri) { CoTaskMemFree (l_uri); }
    return S_OK;
}

static ICoreWebView2NewWindowRequestedEventHandlerVtbl sbw_new_window_vtbl = {
    ICoreWebView2NewWindowRequestedEventHandler_sbw_query,
    ICoreWebView2NewWindowRequestedEventHandler_sbw_add_ref,
    ICoreWebView2NewWindowRequestedEventHandler_sbw_release,
    sbw_on_new_window
};

/* --- DocumentTitleChanged ------------------------------------------------------------------ */

SBW_HANDLER_UNKNOWN (ICoreWebView2DocumentTitleChangedEventHandler)

static HRESULT STDMETHODCALLTYPE sbw_on_title (ICoreWebView2DocumentTitleChangedEventHandler *a_this,
        ICoreWebView2 *a_sender, IUnknown *a_args) {
    sbw_handler_t *l_self = (sbw_handler_t *) a_this;
    LPWSTR l_title = NULL;
    if (SUCCEEDED (ICoreWebView2_get_DocumentTitle (a_sender, &l_title))) {
        sbw_push_wide (l_self->engine, SBW_EVENT_TITLE, 0, 0, 0, l_title);
        if (l_title) { CoTaskMemFree (l_title); }
    }
    return S_OK;
}

static ICoreWebView2DocumentTitleChangedEventHandlerVtbl sbw_title_vtbl = {
    ICoreWebView2DocumentTitleChangedEventHandler_sbw_query,
    ICoreWebView2DocumentTitleChangedEventHandler_sbw_add_ref,
    ICoreWebView2DocumentTitleChangedEventHandler_sbw_release,
    sbw_on_title
};

/* --- NavigationCompleted: the end of a main-frame load ------------------------------------ */

static const char *sbw_web_error_name (COREWEBVIEW2_WEB_ERROR_STATUS a_status) {
    switch (a_status) {
    case COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_COMMON_NAME_IS_INCORRECT: return "certificate common name is incorrect";
    case COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_EXPIRED: return "certificate expired";
    case COREWEBVIEW2_WEB_ERROR_STATUS_CLIENT_CERTIFICATE_CONTAINS_ERRORS: return "client certificate contains errors";
    case COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_REVOKED: return "certificate revoked";
    case COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_IS_INVALID: return "certificate is invalid";
    case COREWEBVIEW2_WEB_ERROR_STATUS_SERVER_UNREACHABLE: return "server unreachable";
    case COREWEBVIEW2_WEB_ERROR_STATUS_TIMEOUT: return "timeout";
    case COREWEBVIEW2_WEB_ERROR_STATUS_ERROR_HTTP_INVALID_SERVER_RESPONSE: return "invalid server response";
    case COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_ABORTED: return "connection aborted";
    case COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_RESET: return "connection reset";
    case COREWEBVIEW2_WEB_ERROR_STATUS_DISCONNECTED: return "disconnected";
    case COREWEBVIEW2_WEB_ERROR_STATUS_CANNOT_CONNECT: return "cannot connect";
    case COREWEBVIEW2_WEB_ERROR_STATUS_HOST_NAME_NOT_RESOLVED: return "host name not resolved";
    case COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED: return "operation canceled";
    case COREWEBVIEW2_WEB_ERROR_STATUS_REDIRECT_FAILED: return "redirect failed";
    case COREWEBVIEW2_WEB_ERROR_STATUS_UNEXPECTED_ERROR: return "unexpected error";
    default: return "unknown error";
    }
}

SBW_HANDLER_UNKNOWN (ICoreWebView2NavigationCompletedEventHandler)

static HRESULT STDMETHODCALLTYPE sbw_on_navigation_completed (ICoreWebView2NavigationCompletedEventHandler *a_this,
        ICoreWebView2 *a_sender, ICoreWebView2NavigationCompletedEventArgs *a_args) {
    sbw_handler_t *l_self = (sbw_handler_t *) a_this;
    BOOL l_success = FALSE;
    COREWEBVIEW2_WEB_ERROR_STATUS l_status = COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
    ICoreWebView2NavigationCompletedEventArgs_get_IsSuccess (a_args, &l_success);
    ICoreWebView2NavigationCompletedEventArgs_get_WebErrorStatus (a_args, &l_status);
    sbw_log ("navigation completed engine=%d success=%d status=%d", l_self->engine, (int) l_success, (int) l_status);
    if (l_success) {
        sbw_push (l_self->engine, SBW_EVENT_LOADED, 0, 0, 0, "", NULL, NULL);
    } else if (l_status != COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED) {
        sbw_push (l_self->engine, SBW_EVENT_LOADED, 1, 0, 0, sbw_web_error_name (l_status), NULL, NULL);
    }
    return S_OK;
}

static ICoreWebView2NavigationCompletedEventHandlerVtbl sbw_navigation_completed_vtbl = {
    ICoreWebView2NavigationCompletedEventHandler_sbw_query,
    ICoreWebView2NavigationCompletedEventHandler_sbw_add_ref,
    ICoreWebView2NavigationCompletedEventHandler_sbw_release,
    sbw_on_navigation_completed
};

/* --- ExecuteScript completion: only a script that did not start is reported here ---------- */

#define SBW_EVALUATING L"\"sb-evaluating\""

SBW_HANDLER_UNKNOWN (ICoreWebView2ExecuteScriptCompletedHandler)

static HRESULT STDMETHODCALLTYPE sbw_on_script_done (ICoreWebView2ExecuteScriptCompletedHandler *a_this,
        HRESULT a_error, LPCWSTR a_result) {
    sbw_handler_t *l_self = (sbw_handler_t *) a_this;
    if (l_self->extra > 0 && (FAILED (a_error) || !a_result || wcscmp (a_result, SBW_EVALUATING) != 0)) {
        /* The wrapper did not run: the script did not compile, or the page refused it. */
        sbw_push (l_self->engine, SBW_EVENT_EVALUATED, l_self->extra, 1, 0,
                  "\"the script could not be compiled or run\"", NULL, NULL);
    }
    return S_OK;
}

static ICoreWebView2ExecuteScriptCompletedHandlerVtbl sbw_script_done_vtbl = {
    ICoreWebView2ExecuteScriptCompletedHandler_sbw_query,
    ICoreWebView2ExecuteScriptCompletedHandler_sbw_add_ref,
    ICoreWebView2ExecuteScriptCompletedHandler_sbw_release,
    sbw_on_script_done
};

/* --- AddScriptToExecuteOnDocumentCreated completion: keep the id ------------------------- */

SBW_HANDLER_UNKNOWN (ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler)

static HRESULT STDMETHODCALLTYPE sbw_on_script_added (ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler *a_this,
        HRESULT a_error, LPCWSTR a_id) {
    sbw_handler_t *l_self = (sbw_handler_t *) a_this;
    sbw_engine_t *l_engine = sbw_engine (l_self->engine);
    sbw_script_t *l_script;
    size_t l_n;
    if (l_engine && l_self->extra >= 0 && l_self->extra < SBW_MAX_SCRIPTS && SUCCEEDED (a_error) && a_id) {
        l_script = &l_engine->scripts[l_self->extra];
        if (l_script->in_use && l_script->removed) {
            if (l_engine->view) { ICoreWebView2_RemoveScriptToExecuteOnDocumentCreated (l_engine->view, a_id); }
            l_script->in_use = 0;
            l_script->removed = 0;
        } else if (l_script->in_use) {
            l_n = wcslen (a_id) + 1;
            l_script->id = (wchar_t *) malloc (sizeof (wchar_t) * l_n);
            if (l_script->id) { memcpy (l_script->id, a_id, sizeof (wchar_t) * l_n); }
        }
    }
    return S_OK;
}

static ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandlerVtbl sbw_script_added_vtbl = {
    ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler_sbw_query,
    ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler_sbw_add_ref,
    ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler_sbw_release,
    sbw_on_script_added
};

/* --- WebResourceRequested: set_html_with_base answers its URL with the page --------------- */

/* Append `a_text' (`a_n' bytes) to `a_out' with &, < and > escaped; `a_out' has room. */
static size_t sbw_append_escaped (char *a_out, size_t a_at, const char *a_text, size_t a_n) {
    size_t i;
    for (i = 0; i < a_n; i++) {
        if (a_text[i] == '&') { memcpy (a_out + a_at, "&amp;", 5); a_at += 5; }
        else if (a_text[i] == '<') { memcpy (a_out + a_at, "&lt;", 4); a_at += 4; }
        else if (a_text[i] == '>') { memcpy (a_out + a_at, "&gt;", 4); a_at += 4; }
        else { a_out[a_at++] = a_text[i]; }
    }
    return a_at;
}

/* The echo page for `a_request': its method, a line break, its body, in <pre id="echo">. */
static char *sbw_echo_page (ICoreWebView2WebResourceRequest *a_request) {
    LPWSTR l_method = NULL;
    char *l_method_8;
    IStream *l_content = NULL;
    char *l_body = NULL;
    size_t l_count = 0, l_room = 0;
    ULONG l_read;
    char l_buffer[4096];
    char *l_page;
    size_t l_at;
    const char *l_head = "<html><head><title>echo</title></head><body><pre id=\"echo\">";
    const char *l_tail = "</pre></body></html>";
    ICoreWebView2WebResourceRequest_get_Method (a_request, &l_method);
    l_method_8 = sbw_utf8 (l_method);
    if (l_method) { CoTaskMemFree (l_method); }
    if (SUCCEEDED (ICoreWebView2WebResourceRequest_get_Content (a_request, &l_content)) && l_content) {
        while (SUCCEEDED (l_content->lpVtbl->Read (l_content, l_buffer, sizeof (l_buffer), &l_read)) && l_read > 0) {
            if (l_count + l_read > l_room) {
                l_room = (l_count + l_read) * 2;
                l_body = (char *) realloc (l_body, l_room);
                if (!l_body) { l_count = 0; break; }
            }
            memcpy (l_body + l_count, l_buffer, l_read);
            l_count += l_read;
        }
        l_content->lpVtbl->Release (l_content);
    }
    l_page = (char *) malloc (strlen (l_head) + strlen (l_tail) + 5 * (l_count + (l_method_8 ? strlen (l_method_8) : 0)) + 8);
    if (l_page) {
        l_at = 0;
        memcpy (l_page, l_head, strlen (l_head));
        l_at = strlen (l_head);
        if (l_method_8) { l_at = sbw_append_escaped (l_page, l_at, l_method_8, strlen (l_method_8)); }
        l_page[l_at++] = '\n';
        if (l_body) { l_at = sbw_append_escaped (l_page, l_at, l_body, l_count); }
        memcpy (l_page + l_at, l_tail, strlen (l_tail) + 1);
    }
    free (l_body);
    free (l_method_8);
    return l_page;
}

/* Answer `a_args' with the HTML `a_html'. */
static void sbw_respond_html (sbw_engine_t *a_engine, ICoreWebView2WebResourceRequestedEventArgs *a_args, const char *a_html) {
    ICoreWebView2WebResourceResponse *l_response = NULL;
    IStream *l_stream = SHCreateMemStream ((const BYTE *) a_html, (UINT) strlen (a_html));
    if (l_stream) {
        if (SUCCEEDED (ICoreWebView2Environment_CreateWebResourceResponse (a_engine->environment, l_stream,
                200, L"OK", L"Content-Type: text/html; charset=utf-8", &l_response)) && l_response) {
            ICoreWebView2WebResourceRequestedEventArgs_put_Response (a_args, l_response);
            ICoreWebView2WebResourceResponse_Release (l_response);
        }
        l_stream->lpVtbl->Release (l_stream);
    }
}

SBW_HANDLER_UNKNOWN (ICoreWebView2WebResourceRequestedEventHandler)

static HRESULT STDMETHODCALLTYPE sbw_on_resource (ICoreWebView2WebResourceRequestedEventHandler *a_this,
        ICoreWebView2 *a_sender, ICoreWebView2WebResourceRequestedEventArgs *a_args) {
    sbw_handler_t *l_self = (sbw_handler_t *) a_this;
    sbw_engine_t *l_engine = sbw_engine (l_self->engine);
    ICoreWebView2WebResourceRequest *l_request = NULL;
    LPWSTR l_uri = NULL;
    char *l_echo;
    if (!l_engine || !l_engine->environment) { return S_OK; }
    if (SUCCEEDED (ICoreWebView2WebResourceRequestedEventArgs_get_Request (a_args, &l_request)) && l_request) {
        if (SUCCEEDED (ICoreWebView2WebResourceRequest_get_Uri (l_request, &l_uri)) && l_uri) {
            if (l_engine->served_url && l_engine->served_html && wcscmp (l_uri, l_engine->served_url) == 0) {
                sbw_respond_html (l_engine, a_args, l_engine->served_html);
            } else if (l_engine->echo_url && wcscmp (l_uri, l_engine->echo_url) == 0) {
                l_echo = sbw_echo_page (l_request);
                if (l_echo) {
                    sbw_respond_html (l_engine, a_args, l_echo);
                    free (l_echo);
                }
            }
        }
        if (l_uri) { CoTaskMemFree (l_uri); }
        ICoreWebView2WebResourceRequest_Release (l_request);
    }
    return S_OK;
}

static ICoreWebView2WebResourceRequestedEventHandlerVtbl sbw_resource_vtbl = {
    ICoreWebView2WebResourceRequestedEventHandler_sbw_query,
    ICoreWebView2WebResourceRequestedEventHandler_sbw_add_ref,
    ICoreWebView2WebResourceRequestedEventHandler_sbw_release,
    sbw_on_resource
};

/* ------------------------------------------------------------------------------------------ */
/* Window: size hints in logical pixels, closing, showing without the focus                   */
/* ------------------------------------------------------------------------------------------ */

typedef UINT (WINAPI *sbw_dpi_for_window_t) (HWND);
typedef BOOL (WINAPI *sbw_adjust_for_dpi_t) (LPRECT, DWORD, BOOL, DWORD, UINT);

static UINT sbw_dpi (HWND a_window) {
    sbw_dpi_for_window_t l_function = (sbw_dpi_for_window_t)
        GetProcAddress (GetModuleHandleW (L"user32.dll"), "GetDpiForWindow");
    UINT l_result = 0;
    if (l_function && a_window) { l_result = l_function (a_window); }
    return l_result > 0 ? l_result : 96;
}

/* The frame size of `a_window' for a content size of `a_width' by `a_height' logical pixels. */
static SIZE sbw_frame_for (HWND a_window, int a_width, int a_height) {
    sbw_adjust_for_dpi_t l_adjust = (sbw_adjust_for_dpi_t)
        GetProcAddress (GetModuleHandleW (L"user32.dll"), "AdjustWindowRectExForDpi");
    UINT l_dpi = sbw_dpi (a_window);
    DWORD l_style = (DWORD) GetWindowLongW (a_window, GWL_STYLE);
    DWORD l_ex_style = (DWORD) GetWindowLongW (a_window, GWL_EXSTYLE);
    RECT l_rect;
    SIZE l_result;
    l_rect.left = 0;
    l_rect.top = 0;
    l_rect.right = MulDiv (a_width, (int) l_dpi, 96);
    l_rect.bottom = MulDiv (a_height, (int) l_dpi, 96);
    if (l_adjust) {
        l_adjust (&l_rect, l_style, FALSE, l_ex_style, l_dpi);
    } else {
        AdjustWindowRectEx (&l_rect, l_style, FALSE, l_ex_style);
    }
    l_result.cx = l_rect.right - l_rect.left;
    l_result.cy = l_rect.bottom - l_rect.top;
    return l_result;
}

/* The content size of the engine's window, in logical pixels. */
static int sbw_content_size (int a_id, int a_height) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    RECT l_rect;
    UINT l_dpi;
    if (!l_engine || !l_engine->window || !IsWindow (l_engine->window)) { return 0; }
    GetClientRect (l_engine->window, &l_rect);
    l_dpi = sbw_dpi (l_engine->window);
    if (a_height) {
        return MulDiv (l_rect.bottom - l_rect.top, 96, (int) l_dpi);
    }
    return MulDiv (l_rect.right - l_rect.left, 96, (int) l_dpi);
}

static LRESULT CALLBACK sbw_window_procedure (HWND a_window, UINT a_message, WPARAM a_w, LPARAM a_l) {
    sbw_engine_t *l_engine = sbw_engine_for_window (a_window);
    WNDPROC l_old = l_engine ? l_engine->old_proc : NULL;
    LRESULT l_result;
    MINMAXINFO *l_info;
    WINDOWPOS *l_position;
    SIZE l_frame;
    int l_id;
    if (!l_engine || !l_old) {
        return DefWindowProcW (a_window, a_message, a_w, a_l);
    }
    l_id = (int) (l_engine - sbw_engines) + 1;
    switch (a_message) {
    case WM_GETMINMAXINFO:
        l_result = CallWindowProcW (l_old, a_window, a_message, a_w, a_l);
        l_info = (MINMAXINFO *) a_l;
        if (l_engine->min_w > 0 && l_engine->min_h > 0) {
            l_frame = sbw_frame_for (a_window, l_engine->min_w, l_engine->min_h);
            l_info->ptMinTrackSize.x = l_frame.cx;
            l_info->ptMinTrackSize.y = l_frame.cy;
        }
        if (l_engine->max_w > 0 && l_engine->max_h > 0) {
            l_frame = sbw_frame_for (a_window, l_engine->max_w, l_engine->max_h);
            l_info->ptMaxTrackSize.x = l_frame.cx;
            l_info->ptMaxTrackSize.y = l_frame.cy;
            l_info->ptMaxSize.x = l_frame.cx;
            l_info->ptMaxSize.y = l_frame.cy;
        }
        return 0;
    case WM_WINDOWPOSCHANGING:
        if (l_engine->suppress_show) {
            l_position = (WINDOWPOS *) a_l;
            l_position->flags &= ~SWP_SHOWWINDOW;
            l_position->flags |= SWP_NOACTIVATE;
        }
        break;
    case WM_DESTROY:
        if (!l_engine->closed) {
            l_engine->closed = 1;
            sbw_push (l_id, SBW_EVENT_CLOSED, 0, 0, 0, NULL, NULL, NULL);
        }
        break;
    default:
        break;
    }
    return CallWindowProcW (l_old, a_window, a_message, a_w, a_l);
}

/* Resize the engine's own window to a content size, clamped by its hints. */
static void sbw_apply_size (sbw_engine_t *a_engine, int a_width, int a_height) {
    SIZE l_frame;
    if (!a_engine->owns_window || !a_engine->window || !IsWindow (a_engine->window)) { return; }
    if (a_engine->min_w > 0 && a_width < a_engine->min_w) { a_width = a_engine->min_w; }
    if (a_engine->min_h > 0 && a_height < a_engine->min_h) { a_height = a_engine->min_h; }
    if (a_engine->max_w > 0 && a_width > a_engine->max_w) { a_width = a_engine->max_w; }
    if (a_engine->max_h > 0 && a_height > a_engine->max_h) { a_height = a_engine->max_h; }
    l_frame = sbw_frame_for (a_engine->window, a_width, a_height);
    SetWindowPos (a_engine->window, NULL, 0, 0, l_frame.cx, l_frame.cy,
                  SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOMOVE | SWP_FRAMECHANGED);
}

static void sbw_set_resizable (sbw_engine_t *a_engine, int a_resizable) {
    LONG l_style = GetWindowLongW (a_engine->window, GWL_STYLE);
    if (a_resizable) {
        l_style |= (WS_THICKFRAME | WS_MAXIMIZEBOX);
    } else {
        l_style &= ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
    }
    SetWindowLongW (a_engine->window, GWL_STYLE, l_style);
}

/* Size hints: 0 none, 1 min, 2 max, 3 fixed. A hint holds against later sizes. */
static void sbw_set_size (int a_id, int a_width, int a_height, int a_hint) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    if (!l_engine || !l_engine->owns_window || !l_engine->window) { return; }
    switch (a_hint) {
    case 1:
        if (l_engine->fixed) {
            l_engine->fixed = 0;
            l_engine->max_w = 0;
            l_engine->max_h = 0;
            sbw_set_resizable (l_engine, 1);
        }
        l_engine->min_w = a_width;
        l_engine->min_h = a_height;
        if (l_engine->max_w > 0 && (l_engine->max_w < a_width || l_engine->max_h < a_height)) {
            l_engine->max_w = 0;
            l_engine->max_h = 0;
        }
        sbw_apply_size (l_engine, sbw_content_size (a_id, 0), sbw_content_size (a_id, 1));
        break;
    case 2:
        if (l_engine->fixed) {
            l_engine->fixed = 0;
            l_engine->min_w = 0;
            l_engine->min_h = 0;
            sbw_set_resizable (l_engine, 1);
        }
        l_engine->max_w = a_width;
        l_engine->max_h = a_height;
        if (l_engine->min_w > 0 && (l_engine->min_w > a_width || l_engine->min_h > a_height)) {
            l_engine->min_w = 0;
            l_engine->min_h = 0;
        }
        sbw_apply_size (l_engine, sbw_content_size (a_id, 0), sbw_content_size (a_id, 1));
        break;
    case 3:
        l_engine->fixed = 1;
        l_engine->min_w = a_width;
        l_engine->min_h = a_height;
        l_engine->max_w = a_width;
        l_engine->max_h = a_height;
        sbw_set_resizable (l_engine, 0);
        sbw_apply_size (l_engine, a_width, a_height);
        break;
    default:
        sbw_apply_size (l_engine, a_width, a_height);
        break;
    }
}

/* Put the engine's own window on screen without taking the focus. */
static void sbw_show (int a_id) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    if (l_engine && l_engine->owns_window && l_engine->window && IsWindow (l_engine->window)
            && !IsWindowVisible (l_engine->window)) {
        ShowWindow (l_engine->window, SW_SHOWNOACTIVATE);
    }
}

typedef struct {
    HWND own;
    DWORD browser_process;
    int count;
} sbw_count_t;

/* Is `a_window' the window of another live engine? */
static int sbw_is_other_engine_window (HWND a_window, HWND a_own) {
    int i;
    for (i = 0; i < SBW_MAX_ENGINES; i++) {
        if (sbw_engines[i].in_use && sbw_engines[i].window == a_window && a_window != a_own) { return 1; }
    }
    return 0;
}

static BOOL CALLBACK sbw_count_window (HWND a_window, LPARAM a_l) {
    sbw_count_t *l_count = (sbw_count_t *) a_l;
    HWND l_owner;
    DWORD l_process = 0;
    if (IsWindowVisible (a_window) && !sbw_is_other_engine_window (a_window, l_count->own)) {
        GetWindowThreadProcessId (a_window, &l_process);
        l_owner = GetWindow (a_window, GW_OWNER);
        if (a_window == l_count->own || (l_owner && l_owner == l_count->own)
                || ((l_process == GetCurrentProcessId () || (l_count->browser_process && l_process == l_count->browser_process))
                    && GetParent (a_window) == NULL
                    && (GetWindowLongW (a_window, GWL_STYLE) & WS_CAPTION) == WS_CAPTION)) {
            l_count->count = l_count->count + 1;
        }
    }
    return TRUE;
}

/* Test hook: the engine's own window, if shown, and every other visible captioned top-level
   window of this process or of the engine's WebView2 browser process (where a new window the
   page opened would appear), other engines' windows left out. */
static int sbw_window_count (int a_id) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    sbw_count_t l_count;
    UINT32 l_browser = 0;
    l_count.own = l_engine ? l_engine->window : NULL;
    if (l_engine && l_engine->view) { ICoreWebView2_get_BrowserProcessId (l_engine->view, &l_browser); }
    l_count.browser_process = (DWORD) l_browser;
    l_count.count = 0;
    EnumWindows (sbw_count_window, (LPARAM) &l_count);
    return l_count.count;
}

static int sbw_is_resizable (int a_id) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    if (!l_engine || !l_engine->window || !IsWindow (l_engine->window)) { return 0; }
    return (GetWindowLongW (l_engine->window, GWL_STYLE) & WS_THICKFRAME) != 0;
}

/* ------------------------------------------------------------------------------------------ */
/* Scripts                                                                                    */
/* ------------------------------------------------------------------------------------------ */

static void sbw_execute (sbw_engine_t *a_engine, int a_id, const char *a_script, int a_ticket) {
    wchar_t *l_script;
    sbw_handler_t *l_handler = NULL;
    if (!a_engine->view) { return; }
    l_script = sbw_wide (a_script);
    if (a_ticket > 0) {
        l_handler = sbw_new_handler (&sbw_script_done_vtbl, &IID_ICoreWebView2ExecuteScriptCompletedHandler,
                                     a_id, a_ticket);
    }
    if (l_script) {
        ICoreWebView2_ExecuteScript (a_engine->view, l_script,
                                     (ICoreWebView2ExecuteScriptCompletedHandler *) l_handler);
        free (l_script);
    }
    if (l_handler) { sbw_handler_release (l_handler); }
}

/* Add a document-start script under `a_name' (empty for the bridge), and run it on the page now. */
static void sbw_add_script (int a_id, const char *a_name, const char *a_script) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    sbw_handler_t *l_handler;
    wchar_t *l_script;
    int i, l_slot = -1;
    if (!l_engine || !l_engine->view) { return; }
    for (i = 0; i < SBW_MAX_SCRIPTS && l_slot < 0; i++) {
        if (!l_engine->scripts[i].in_use) { l_slot = i; }
    }
    if (l_slot < 0) { return; }
    memset (&l_engine->scripts[l_slot], 0, sizeof (sbw_script_t));
    l_engine->scripts[l_slot].in_use = 1;
    strncpy (l_engine->scripts[l_slot].name, a_name ? a_name : "", SBW_NAME_MAX - 1);
    l_handler = sbw_new_handler (&sbw_script_added_vtbl,
        &IID_ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler, a_id, l_slot);
    l_script = sbw_wide (a_script);
    if (l_script && l_handler) {
        ICoreWebView2_AddScriptToExecuteOnDocumentCreated (l_engine->view, l_script,
            (ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler *) l_handler);
    }
    free (l_script);
    if (l_handler) { sbw_handler_release (l_handler); }
    sbw_execute (l_engine, a_id, a_script, 0);
}

/* Remove the document-start script added under `a_name'. */
static void sbw_remove_script (int a_id, const char *a_name) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    int i;
    if (!l_engine || !a_name || !a_name[0]) { return; }
    for (i = 0; i < SBW_MAX_SCRIPTS; i++) {
        if (l_engine->scripts[i].in_use && !l_engine->scripts[i].removed
                && strcmp (l_engine->scripts[i].name, a_name) == 0) {
            if (l_engine->scripts[i].id) {
                if (l_engine->view) {
                    ICoreWebView2_RemoveScriptToExecuteOnDocumentCreated (l_engine->view, l_engine->scripts[i].id);
                }
                free (l_engine->scripts[i].id);
                l_engine->scripts[i].id = NULL;
                l_engine->scripts[i].in_use = 0;
            } else {
                l_engine->scripts[i].removed = 1;
            }
        }
    }
}

static void sbw_eval (int a_id, const char *a_script) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    if (l_engine) { sbw_execute (l_engine, a_id, a_script, 0); }
}

/* Run the engine's evaluate wrapper; its result comes back as a web message with the ticket. */
static void sbw_evaluate (int a_id, int a_ticket, const char *a_script) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    if (l_engine) { sbw_execute (l_engine, a_id, a_script, a_ticket); }
}

/* ------------------------------------------------------------------------------------------ */
/* Navigation                                                                                 */
/* ------------------------------------------------------------------------------------------ */

static void sbw_navigate (int a_id, const char *a_url) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    if (!l_engine) { return; }
    l_engine->pass_pending = l_engine->pass_pending + 1;
    webview_navigate (l_engine->w, a_url);
}

/* Load `a_html' as the document at `a_base': the URL is answered with the page. set_html's base
   comes from shared code (SB_SCRIPTS.set_html_base: https://simple-browser.invalid/page-N). Not
   NavigateToString, whose data: URL page cannot even follow a link to about:blank. */
static void sbw_set_html_with_base (int a_id, const char *a_html, const char *a_base) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    wchar_t *l_base;
    if (!l_engine) { return; }
    if (!l_engine->view || !l_engine->environment) {
        l_engine->pass_pending = l_engine->pass_pending + 1;
        webview_set_html (l_engine->w, a_html);
        return;
    }
    if (l_engine->served_url) {
        ICoreWebView2_RemoveWebResourceRequestedFilter (l_engine->view, l_engine->served_url,
                                                        COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
        free (l_engine->served_url);
    }
    free (l_engine->served_html);
    l_engine->served_html = sbw_copy (a_html);
    l_engine->served_url = sbw_wide (a_base);
    ICoreWebView2_AddWebResourceRequestedFilter (l_engine->view, l_engine->served_url,
                                                 COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
    l_base = sbw_wide (a_base);
    l_engine->pass_pending = l_engine->pass_pending + 1;
    ICoreWebView2_Navigate (l_engine->view, l_base);
    free (l_base);
}

/* Test hook: answer requests for `a_url' with the request's method and body. */
static void sbw_set_echo (int a_id, const char *a_url) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    if (!l_engine || !l_engine->view) { return; }
    if (l_engine->echo_url) {
        ICoreWebView2_RemoveWebResourceRequestedFilter (l_engine->view, l_engine->echo_url,
                                                        COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
        free (l_engine->echo_url);
    }
    l_engine->echo_url = sbw_wide (a_url);
    if (l_engine->echo_url) {
        ICoreWebView2_AddWebResourceRequestedFilter (l_engine->view, l_engine->echo_url,
                                                     COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
    }
}

/* Let the next navigation of frame `a_frame' (0 the main frame) through: a replay the page
   makes itself (a held form submitted again). */
static void sbw_pass_next (int a_id, int a_frame) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    sbw_frame_t *l_frame = a_frame ? sbw_frame (a_id, a_frame) : NULL;
    if (l_frame) {
        l_frame->pass_pending = l_frame->pass_pending + 1;
    } else if (l_engine && a_frame == 0) {
        l_engine->pass_pending = l_engine->pass_pending + 1;
    }
}

/* Run `a_script' in frame `a_frame' (0 the main frame); its result is discarded. */
static void sbw_eval_in (int a_id, int a_frame, const char *a_script) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    sbw_frame_t *l_frame;
    wchar_t *l_script;
    if (!l_engine) { return; }
    sbw_log ("eval in engine=%d frame=%d script=%.200s", a_id, a_frame, a_script ? a_script : "");
    if (a_frame == 0) {
        sbw_execute (l_engine, a_id, a_script, 0);
    } else if ((l_frame = sbw_frame (a_id, a_frame)) != NULL) {
        l_script = sbw_wide (a_script);
        if (l_script) {
            ICoreWebView2Frame2_ExecuteScript (l_frame->frame, l_script, NULL);
            free (l_script);
        }
    }
}

static void sbw_set_deciding (int a_id, int a_on) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    if (l_engine) { l_engine->deciding = a_on; }
}

static void sbw_decide (int a_id, int a_number, int a_allow) {
    sbw_answer_held (a_id, a_number, a_allow);
}

static void sbw_set_dev_tools (int a_id, int a_on) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    ICoreWebView2Settings *l_settings = NULL;
    if (l_engine && l_engine->view && SUCCEEDED (ICoreWebView2_get_Settings (l_engine->view, &l_settings)) && l_settings) {
        ICoreWebView2Settings_put_AreDevToolsEnabled (l_settings, a_on ? TRUE : FALSE);
        ICoreWebView2Settings_Release (l_settings);
    }
}

/* ------------------------------------------------------------------------------------------ */
/* The pump                                                                                   */
/* ------------------------------------------------------------------------------------------ */

/* Handle this thread's messages for up to `a_ms' milliseconds, or until an event is queued
   for engine `a_id'. WM_QUIT (webview.dll posts one when its last window goes) is dropped. */
static void sbw_pump (int a_id, int a_ms) {
    DWORD l_start = GetTickCount ();
    DWORD l_elapsed;
    MSG l_message;
    for (;;) {
        while (PeekMessageW (&l_message, NULL, 0, 0, PM_REMOVE)) {
            if (l_message.message != WM_QUIT) {
                TranslateMessage (&l_message);
                DispatchMessageW (&l_message);
            }
            if (sbw_has_event (a_id)) { return; }
        }
        if (sbw_has_event (a_id)) { return; }
        l_elapsed = GetTickCount () - l_start;
        if ((int) l_elapsed >= a_ms) { return; }
        MsgWaitForMultipleObjectsEx (0, NULL, (DWORD) a_ms - l_elapsed, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
    }
}

/* ------------------------------------------------------------------------------------------ */
/* Creation and disposal                                                                      */
/* ------------------------------------------------------------------------------------------ */

static void sbw_register (sbw_engine_t *a_engine, int a_id) {
    EventRegistrationToken l_token;
    sbw_handler_t *l_handler;
    ICoreWebView2 *l_view = a_engine->view;

#define SBW_ADD(EVENT, VTBL, IID_NAME, EXTRA, TYPE) \
    l_handler = sbw_new_handler (&VTBL, &IID_NAME, a_id, EXTRA); \
    if (l_handler) { \
        ICoreWebView2_add_##EVENT (l_view, (TYPE *) l_handler, &l_token); \
        sbw_handler_release (l_handler); }

    SBW_ADD (WebMessageReceived, sbw_message_vtbl, IID_ICoreWebView2WebMessageReceivedEventHandler, 0,
             ICoreWebView2WebMessageReceivedEventHandler)
    SBW_ADD (NavigationStarting, sbw_navigation_starting_vtbl, IID_ICoreWebView2NavigationStartingEventHandler, 1,
             ICoreWebView2NavigationStartingEventHandler)
    SBW_ADD (NewWindowRequested, sbw_new_window_vtbl, IID_ICoreWebView2NewWindowRequestedEventHandler, 0,
             ICoreWebView2NewWindowRequestedEventHandler)
    SBW_ADD (DocumentTitleChanged, sbw_title_vtbl, IID_ICoreWebView2DocumentTitleChangedEventHandler, 0,
             ICoreWebView2DocumentTitleChangedEventHandler)
    SBW_ADD (NavigationCompleted, sbw_navigation_completed_vtbl, IID_ICoreWebView2NavigationCompletedEventHandler, 0,
             ICoreWebView2NavigationCompletedEventHandler)
    SBW_ADD (WebResourceRequested, sbw_resource_vtbl, IID_ICoreWebView2WebResourceRequestedEventHandler, 0,
             ICoreWebView2WebResourceRequestedEventHandler)
#undef SBW_ADD
    {
        ICoreWebView2_4 *l_view_4 = NULL;
        if (SUCCEEDED (ICoreWebView2_QueryInterface (l_view, &IID_ICoreWebView2_4, (void **) &l_view_4)) && l_view_4) {
            l_handler = sbw_new_handler (&sbw_frame_created_vtbl, &IID_ICoreWebView2FrameCreatedEventHandler, a_id, 0);
            if (l_handler) {
                ICoreWebView2_4_add_FrameCreated (l_view_4, (ICoreWebView2FrameCreatedEventHandler *) l_handler, &l_token);
                sbw_handler_release (l_handler);
            }
            ICoreWebView2_4_Release (l_view_4);
        }
    }
}

/* A fresh folder in the temporary directory, for an ephemeral engine's user data. */
static void sbw_make_data_folder (sbw_engine_t *a_engine) {
    wchar_t l_temp[MAX_PATH];
    DWORD l_n = GetTempPathW (MAX_PATH, l_temp);
    if (l_n == 0 || l_n >= MAX_PATH - 64) { a_engine->data_folder[0] = L'\0'; return; }
    sbw_folder_serial = sbw_folder_serial + 1;
    _snwprintf (a_engine->data_folder, MAX_PATH - 1, L"%lssimple_browser-%lu-%d-%lu", l_temp,
                (unsigned long) GetCurrentProcessId (), sbw_folder_serial, (unsigned long) GetTickCount ());
    a_engine->data_folder[MAX_PATH - 1] = L'\0';
    CreateDirectoryW (a_engine->data_folder, NULL);
}

/* Create an engine: its own window (`a_parent' NULL) or inside `a_parent'. 0 on failure. */
static int sbw_create (int a_ephemeral, int a_debug, void *a_parent) {
    sbw_engine_t *l_engine = NULL;
    MSG l_message;
    wchar_t l_saved[MAX_PATH * 2];
    DWORD l_saved_n = 0;
    void *l_handle;
    int i, l_id = 0;
    for (i = 0; i < SBW_MAX_ENGINES && !l_engine; i++) {
        if (!sbw_engines[i].in_use) { l_engine = &sbw_engines[i]; l_id = i + 1; }
    }
    if (!l_engine) { sbw_last_error_code = -1; return 0; }
    memset (l_engine, 0, sizeof (sbw_engine_t));
    l_engine->in_use = 1;
    l_engine->ephemeral = a_ephemeral;
    l_engine->owns_window = a_parent == NULL;
    CoInitializeEx (NULL, COINIT_APARTMENTTHREADED);
    /* A WM_QUIT left by a closed window would cancel webview_create's own loop. */
    while (PeekMessageW (&l_message, NULL, WM_QUIT, WM_QUIT, PM_REMOVE)) { }
    if (a_ephemeral) {
        sbw_make_data_folder (l_engine);
        l_saved_n = GetEnvironmentVariableW (L"WEBVIEW2_USER_DATA_FOLDER", l_saved, MAX_PATH * 2);
        SetEnvironmentVariableW (L"WEBVIEW2_USER_DATA_FOLDER", l_engine->data_folder);
    }
    l_engine->w = webview_create (a_debug ? 1 : 0, a_parent);
    if (a_ephemeral) {
        if (l_saved_n > 0 && l_saved_n < MAX_PATH * 2) {
            SetEnvironmentVariableW (L"WEBVIEW2_USER_DATA_FOLDER", l_saved);
        } else {
            SetEnvironmentVariableW (L"WEBVIEW2_USER_DATA_FOLDER", NULL);
        }
    }
    if (!l_engine->w) {
        sbw_last_error_code = (int) GetLastError ();
        l_engine->in_use = 0;
        return 0;
    }
    l_engine->controller = (ICoreWebView2Controller *)
        webview_get_native_handle (l_engine->w, WEBVIEW_NATIVE_HANDLE_KIND_BROWSER_CONTROLLER);
    if (l_engine->controller) {
        ICoreWebView2Controller_get_CoreWebView2 (l_engine->controller, &l_engine->view);
    }
    if (l_engine->view) {
        ICoreWebView2_2 *l_view_2 = NULL;
        if (SUCCEEDED (ICoreWebView2_QueryInterface (l_engine->view, &IID_ICoreWebView2_2, (void **) &l_view_2)) && l_view_2) {
            ICoreWebView2_2_get_Environment (l_view_2, &l_engine->environment);
            ICoreWebView2_2_Release (l_view_2);
        }
        sbw_register (l_engine, l_id);
    }
    l_handle = webview_get_window (l_engine->w);
    l_engine->window = (HWND) (a_parent ? a_parent : l_handle);
    if (l_engine->owns_window && l_engine->window) {
        l_engine->old_proc = (WNDPROC) SetWindowLongPtrW (l_engine->window, GWLP_WNDPROC,
                                                         (LONG_PTR) sbw_window_procedure);
        /* webview.dll shows its window, with the focus, on its first size; take that first size
           now, hidden, so the window appears only through `show'. */
        l_engine->suppress_show = 1;
        webview_set_size (l_engine->w, 640, 480, WEBVIEW_HINT_NONE);
        ShowWindow (l_engine->window, SW_HIDE);
        l_engine->suppress_show = 0;
    }
    sbw_log ("create engine=%d window=%p view=%p environment=%p folder=%S", l_id, (void *) l_engine->window,
             (void *) l_engine->view, (void *) l_engine->environment, l_engine->data_folder);
    return l_id;
}

static int sbw_last_error (void) { return sbw_last_error_code; }

static void *sbw_window (int a_id) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    return (l_engine && !l_engine->closed) ? (void *) l_engine->window : NULL;
}

static const wchar_t *sbw_data_folder_wide (int a_id) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    return l_engine ? l_engine->data_folder : L"";
}

static int sbw_delete_tree (const wchar_t *a_folder) {
    wchar_t l_pattern[MAX_PATH * 2];
    wchar_t l_path[MAX_PATH * 2];
    WIN32_FIND_DATAW l_data;
    HANDLE l_find;
    int l_ok = 1;
    _snwprintf (l_pattern, MAX_PATH * 2 - 1, L"%ls\\*", a_folder);
    l_pattern[MAX_PATH * 2 - 1] = L'\0';
    l_find = FindFirstFileW (l_pattern, &l_data);
    if (l_find != INVALID_HANDLE_VALUE) {
        do {
            if (wcscmp (l_data.cFileName, L".") != 0 && wcscmp (l_data.cFileName, L"..") != 0) {
                _snwprintf (l_path, MAX_PATH * 2 - 1, L"%ls\\%ls", a_folder, l_data.cFileName);
                l_path[MAX_PATH * 2 - 1] = L'\0';
                if (l_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
                    if (!sbw_delete_tree (l_path)) { l_ok = 0; }
                } else {
                    SetFileAttributesW (l_path, FILE_ATTRIBUTE_NORMAL);
                    if (!DeleteFileW (l_path)) { l_ok = 0; }
                }
            }
        } while (FindNextFileW (l_find, &l_data));
        FindClose (l_find);
    }
    if (!RemoveDirectoryW (a_folder) && GetFileAttributesW (a_folder) != INVALID_FILE_ATTRIBUTES) { l_ok = 0; }
    return l_ok;
}

/* Is the folder `a_folder' (UTF-8) gone? */
static int sbw_folder_gone (const char *a_folder) {
    wchar_t *l_folder = sbw_wide (a_folder);
    int l_result = l_folder ? GetFileAttributesW (l_folder) == INVALID_FILE_ATTRIBUTES : 0;
    free (l_folder);
    return l_result;
}

/* Release the engine: held decisions dropped (their navigations are already canceled),
   webview.dll destroyed, events dropped,
   and an ephemeral engine's data folder deleted once WebView2's processes let go of it. */
static void sbw_dispose (int a_id) {
    sbw_engine_t *l_engine = sbw_engine (a_id);
    wchar_t l_folder[MAX_PATH];
    DWORD l_start;
    MSG l_message;
    int i, l_deleted = 0;
    if (!l_engine) { return; }
    for (i = 0; i < SBW_MAX_HELD; i++) {
        if (sbw_held[i].in_use && sbw_held[i].engine == a_id) {
            sbw_answer_held (a_id, sbw_held[i].number, 0);
        }
    }
    l_engine->disposing = 1;
    for (i = 0; i < SBW_MAX_FRAMES; i++) {
        if (sbw_frames[i].in_use && sbw_frames[i].engine == a_id) { sbw_release_frame (i); }
    }
    for (i = 0; i < SBW_MAX_SCRIPTS; i++) {
        free (l_engine->scripts[i].id);
        l_engine->scripts[i].id = NULL;
    }
    if (l_engine->environment) { ICoreWebView2Environment_Release (l_engine->environment); l_engine->environment = NULL; }
    if (l_engine->view) { ICoreWebView2_Release (l_engine->view); l_engine->view = NULL; }
    webview_destroy (l_engine->w);
    l_engine->w = NULL;
    while (PeekMessageW (&l_message, NULL, WM_QUIT, WM_QUIT, PM_REMOVE)) { }
    wcscpy (l_folder, l_engine->data_folder);
    free (l_engine->served_url);
    free (l_engine->served_html);
    free (l_engine->echo_url);
    sbw_free_event (l_engine->current);
    l_engine->current = NULL;
    l_engine->in_use = 0;
    sbw_drop_events (a_id);
    if (l_folder[0]) {
        /* WebView2's browser process holds the folder for a moment after its last view goes. */
        l_start = GetTickCount ();
        while (!l_deleted && GetTickCount () - l_start < 15000) {
            l_deleted = sbw_delete_tree (l_folder);
            if (!l_deleted) {
                while (PeekMessageW (&l_message, NULL, 0, 0, PM_REMOVE)) {
                    if (l_message.message != WM_QUIT) {
                        TranslateMessage (&l_message);
                        DispatchMessageW (&l_message);
                    }
                }
                Sleep (50);
            }
        }
        sbw_log ("dispose engine=%d folder deleted=%d after %lu ms", a_id, l_deleted,
                 (unsigned long) (GetTickCount () - l_start));
    }
}

#endif /* SB_WIN_H */
