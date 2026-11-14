/*
 * sb_gtk.h - the Linux engine of simple_browser: WebKitGTK 6.0 on GTK 4 (SIMPLE_BROWSER_SPEC.md,
 * section 3).
 *
 * The rules (section 4):
 *   - C never calls Eiffel. Every WebKitGTK callback pushes an event on one process-wide queue,
 *     keyed by engine id; Eiffel takes them with sbg_take after sbg_pump returns.
 *   - sbg_pump is called from a `blocking' external: while it runs, this thread is outside
 *     Eiffel code and other processors' garbage collections do not wait for it. Nothing here
 *     touches an Eiffel object.
 *   - The default GMainContext is pumped; gtk_main and GtkApplication are never used, so the
 *     browser shares the loop with simple_gui's GTK backend in one process.
 *   - Inline C: this header is compiled into every C file whose class has an external that uses
 *     it, so its mutable data is __attribute__((weak)) (SBG_SHARED): one copy for the whole
 *     program, not one per translation unit. Functions are static; they reach only that data.
 *
 * Event kinds (BROWSER_ENGINE): 1 call, 2 evaluated, 3 navigating, 4 new_window,
 * 5 title_changed, 6 loaded, 7 closed.
 *
 * Logging: off unless SB_GTK_LOG is set (to a file name, or to "-" for standard error).
 *
 * Copyright (c) 2025-2026 Larry Rix
 */

#ifndef SB_GTK_H
#define SB_GTK_H

#include <gtk/gtk.h>
#include <webkit/webkit.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef GDK_WINDOWING_X11
#include <gdk/x11/gdkx.h>
#endif

#define SBG_SHARED __attribute__((weak))

#define SBG_MAX_ENGINES 16
#define SBG_MAX_HELD 64
#define SBG_MAX_SCRIPTS 64

#define SBG_EVENT_CALL 1
#define SBG_EVENT_EVALUATED 2
#define SBG_EVENT_NAVIGATING 3
#define SBG_EVENT_NEW_WINDOW 4
#define SBG_EVENT_TITLE 5
#define SBG_EVENT_LOADED 6
#define SBG_EVENT_CLOSED 7

/* Why sbg_create failed (sbg_last_error). */
#define SBG_ERROR_NO_DISPLAY 1
#define SBG_ERROR_NO_ROOM 2
#define SBG_ERROR_BAD_PARENT 3
#define SBG_ERROR_NOT_GUI_THREAD 4

/* ------------------------------------------------------------------------------------------ */
/* Shared data                                                                                */
/* ------------------------------------------------------------------------------------------ */

typedef struct sbg_event_s {
    int engine;
    int kind;
    int a, b, c;
    char *text[3];
    struct sbg_event_s *next;
} sbg_event_t;

typedef struct {
    int in_use;
    char *name;               /* the binding's name; NULL for the bridge and init scripts */
    char *source;
    int all_frames;           /* every frame (init scripts, the frame script), else the top frame */
} sbg_script_t;

typedef struct {
    int kind;                 /* SBG_HINT_FRAME or SBG_HINT_PARENT */
    char *uri;                /* normalized; NULL when the slot is free */
    gint64 at;                /* when it came, monotonic microseconds */
} sbg_hint_t;

#define SBG_MAX_HINTS 16

typedef struct {
    int in_use;
    int disposing;
    unsigned int serial;      /* changes with every engine made in this slot */
    GtkWidget *window;        /* the own window, or the parent's root window (embedded) */
    GtkWidget *parent;        /* embedded: the GtkWindow or GtkBox the view went into */
    GtkWidget *content;       /* the own window's child: a GtkBox holding the view */
    int owns_window;
    int closed;
    WebKitWebView *view;      /* referenced */
    WebKitUserContentManager *content_manager;  /* referenced */
    WebKitNetworkSession *session;              /* referenced */
    GCancellable *cancellable;                  /* every evaluate's; cancelled on dispose */
    int deciding;
    char *pass_url;           /* the program's own load, let through once (normalized) */
    int pass_active;          /* a load let through is under way: its redirects pass too */
    int load_failed;          /* load-failed came for the load under way */
    int has_page;             /* has a load been started? (scripts run "now" only on a page) */
    char *echo_url;           /* test_echo_at's URL (normalized), or NULL */
    sbg_hint_t hints[SBG_MAX_HINTS];  /* the frame script's hints, newest kept */
    int min_w, min_h, max_w, max_h, fixed;  /* size hints, logical pixels; 0 = none */
    int width, height;        /* the content size last asked for */
    sbg_script_t scripts[SBG_MAX_SCRIPTS];
    sbg_event_t *current;     /* the event last taken */
} sbg_engine_t;

typedef struct {
    int in_use;
    int engine;
    int number;
    WebKitPolicyDecision *decision;  /* referenced while held */
    int kind;                 /* BROWSER_ENGINE's navigation kind */
    char *uri;
    char *method;
    int echo;                 /* a request for test_echo_at's URL */
} sbg_held_t;

typedef struct {
    int engine;
    unsigned int serial;
    int ticket;               /* the evaluate's ticket, or the decision number being classified */
} sbg_evaluation_t;

SBG_SHARED sbg_engine_t sbg_engines[SBG_MAX_ENGINES] = {{0}};
SBG_SHARED sbg_held_t sbg_held[SBG_MAX_HELD] = {{0}};
SBG_SHARED sbg_event_t *sbg_queue_head = NULL;
SBG_SHARED sbg_event_t *sbg_queue_tail = NULL;
SBG_SHARED GMutex sbg_lock;
SBG_SHARED int sbg_next_decision = 0;
SBG_SHARED int sbg_last_error_code = 0;
SBG_SHARED GThread *sbg_gui_thread = NULL;
SBG_SHARED volatile gint sbg_wake_pending = 0;

/* ------------------------------------------------------------------------------------------ */
/* Logging                                                                                    */
/* ------------------------------------------------------------------------------------------ */

static void sbg_log (const char *a_format, ...) {
    const char *l_path = g_getenv ("SB_GTK_LOG");
    FILE *l_file;
    va_list l_args;
    if (!l_path || !l_path[0]) { return; }
    l_file = (strcmp (l_path, "-") == 0) ? stderr : fopen (l_path, "a");
    if (l_file) {
        va_start (l_args, a_format);
        fprintf (l_file, "[sb_gtk %lld] ", (long long) (g_get_monotonic_time () / 1000));
        vfprintf (l_file, a_format, l_args);
        fprintf (l_file, "\n");
        va_end (l_args);
        if (l_file == stderr) { fflush (l_file); } else { fclose (l_file); }
    }
}

/* ------------------------------------------------------------------------------------------ */
/* Text                                                                                       */
/* ------------------------------------------------------------------------------------------ */

static char *sbg_copy (const char *a_text) {
    return a_text ? g_strdup (a_text) : NULL;
}

/* `a_text' (UTF-8) as a JSON string literal, quoted; g_free it. */
static char *sbg_json_string (const char *a_text) {
    GString *l_result = g_string_new ("\"");
    const unsigned char *l_p;
    for (l_p = (const unsigned char *) (a_text ? a_text : ""); *l_p; l_p++) {
        switch (*l_p) {
        case '"': g_string_append (l_result, "\\\""); break;
        case '\\': g_string_append (l_result, "\\\\"); break;
        case '\b': g_string_append (l_result, "\\b"); break;
        case '\f': g_string_append (l_result, "\\f"); break;
        case '\n': g_string_append (l_result, "\\n"); break;
        case '\r': g_string_append (l_result, "\\r"); break;
        case '\t': g_string_append (l_result, "\\t"); break;
        default:
            if (*l_p < 0x20) {
                g_string_append_printf (l_result, "\\u%04x", (unsigned int) *l_p);
            } else {
                g_string_append_c (l_result, (char) *l_p);
            }
        }
    }
    g_string_append_c (l_result, '"');
    return g_string_free (l_result, FALSE);
}

/* `a_uri' normalized as WebKit reports a request's URI (an empty http path becomes "/");
   g_free it. */
static char *sbg_normalized_uri (const char *a_uri) {
    GUri *l_uri;
    char *l_result = NULL;
    if (!a_uri) { return NULL; }
    l_uri = g_uri_parse (a_uri, G_URI_FLAGS_SCHEME_NORMALIZE | G_URI_FLAGS_ENCODED, NULL);
    if (l_uri) {
        l_result = g_uri_to_string (l_uri);
        g_uri_unref (l_uri);
    }
    return l_result ? l_result : g_strdup (a_uri);
}

/* ------------------------------------------------------------------------------------------ */
/* Engines and the queue                                                                      */
/* ------------------------------------------------------------------------------------------ */

static int sbg_is_gui_thread (void) {
    return sbg_gui_thread == NULL || g_thread_self () == sbg_gui_thread;
}

static sbg_engine_t *sbg_engine (int a_id) {
    if (a_id >= 1 && a_id <= SBG_MAX_ENGINES && sbg_engines[a_id - 1].in_use) {
        return &sbg_engines[a_id - 1];
    }
    return NULL;
}

/* The engine `a_data' (a signal's user data, the id) names, if it is live and not disposing. */
static sbg_engine_t *sbg_live (gpointer a_data) {
    sbg_engine_t *l_engine = sbg_engine (GPOINTER_TO_INT (a_data));
    return (l_engine && !l_engine->disposing) ? l_engine : NULL;
}

static void sbg_free_event (sbg_event_t *a_event) {
    int i;
    if (a_event) {
        for (i = 0; i < 3; i++) { g_free (a_event->text[i]); }
        g_free (a_event);
    }
}

/* Queue an event for engine `a_id'; the texts are copied. */
static void sbg_push (int a_id, int a_kind, int a_a, int a_b, int a_c,
                      const char *a_t1, const char *a_t2, const char *a_t3) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    sbg_event_t *l_event;
    if (!l_engine || l_engine->disposing) { return; }
    l_event = g_new0 (sbg_event_t, 1);
    l_event->engine = a_id;
    l_event->kind = a_kind;
    l_event->a = a_a;
    l_event->b = a_b;
    l_event->c = a_c;
    l_event->text[0] = sbg_copy (a_t1);
    l_event->text[1] = sbg_copy (a_t2);
    l_event->text[2] = sbg_copy (a_t3);
    g_mutex_lock (&sbg_lock);
    if (sbg_queue_tail) { sbg_queue_tail->next = l_event; } else { sbg_queue_head = l_event; }
    sbg_queue_tail = l_event;
    g_mutex_unlock (&sbg_lock);
    sbg_log ("push engine=%d kind=%d a=%d b=%d c=%d t1=%.200s", a_id, a_kind, a_a, a_b, a_c,
             a_t1 ? a_t1 : "");
}

/* Is an event queued for engine `a_id'? */
static int sbg_has_event (int a_id) {
    sbg_event_t *l_event;
    int l_result = 0;
    g_mutex_lock (&sbg_lock);
    for (l_event = sbg_queue_head; l_event && !l_result; l_event = l_event->next) {
        if (l_event->engine == a_id) { l_result = 1; }
    }
    g_mutex_unlock (&sbg_lock);
    return l_result;
}

/* Take the oldest event for engine `a_id' into its `current'; 0 if none. */
static int sbg_take (int a_id) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    sbg_event_t *l_event, *l_previous = NULL;
    if (!l_engine) { return 0; }
    sbg_free_event (l_engine->current);
    l_engine->current = NULL;
    g_mutex_lock (&sbg_lock);
    for (l_event = sbg_queue_head; l_event; l_previous = l_event, l_event = l_event->next) {
        if (l_event->engine == a_id) {
            if (l_previous) { l_previous->next = l_event->next; } else { sbg_queue_head = l_event->next; }
            if (sbg_queue_tail == l_event) { sbg_queue_tail = l_previous; }
            l_event->next = NULL;
            l_engine->current = l_event;
            break;
        }
    }
    g_mutex_unlock (&sbg_lock);
    return l_engine->current != NULL;
}

static int sbg_current_kind (int a_id) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    return (l_engine && l_engine->current) ? l_engine->current->kind : 0;
}

static int sbg_current_a (int a_id) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    return (l_engine && l_engine->current) ? l_engine->current->a : 0;
}

static int sbg_current_b (int a_id) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    return (l_engine && l_engine->current) ? l_engine->current->b : 0;
}

static int sbg_current_c (int a_id) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    return (l_engine && l_engine->current) ? l_engine->current->c : 0;
}

static const char *sbg_current_text (int a_id, int a_index) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    const char *l_result = NULL;
    if (l_engine && l_engine->current && a_index >= 1 && a_index <= 3) {
        l_result = l_engine->current->text[a_index - 1];
    }
    return l_result ? l_result : "";
}

/* Drop every queued event of engine `a_id'. */
static void sbg_drop_events (int a_id) {
    sbg_event_t *l_event, *l_previous = NULL, *l_next;
    g_mutex_lock (&sbg_lock);
    for (l_event = sbg_queue_head; l_event; l_event = l_next) {
        l_next = l_event->next;
        if (l_event->engine == a_id) {
            if (l_previous) { l_previous->next = l_next; } else { sbg_queue_head = l_next; }
            if (sbg_queue_tail == l_event) { sbg_queue_tail = l_previous; }
            sbg_free_event (l_event);
        } else {
            l_previous = l_event;
        }
    }
    g_mutex_unlock (&sbg_lock);
}

/* ------------------------------------------------------------------------------------------ */
/* Navigation decisions                                                                       */
/* ------------------------------------------------------------------------------------------ */

/* The kinds of frame hint the engine's frame script posts (channel sb_gtk_frame). */
#define SBG_HINT_FRAME 1      /* a frame started a navigation of its own (link, form, script) */
#define SBG_HINT_PARENT 2     /* a page set an iframe's src: the iframe's navigation, not asked */
#define SBG_HINT_LIFE_US 3000000

/* Keep frame hint `a_kind' for `a_uri' (normalized) on engine `a_engine'. */
static void sbg_add_hint (sbg_engine_t *a_engine, int a_kind, const char *a_uri) {
    int i, l_slot = 0;
    gint64 l_oldest = G_MAXINT64;
    for (i = 0; i < SBG_MAX_HINTS; i++) {
        if (!a_engine->hints[i].uri) { l_slot = i; break; }
        if (a_engine->hints[i].at < l_oldest) { l_oldest = a_engine->hints[i].at; l_slot = i; }
    }
    g_free (a_engine->hints[l_slot].uri);
    a_engine->hints[l_slot].kind = a_kind;
    a_engine->hints[l_slot].uri = sbg_normalized_uri (a_uri);
    a_engine->hints[l_slot].at = g_get_monotonic_time ();
}

/* Take the oldest live hint of `a_kind' for `a_uri'; 0 if there is none. */
static int sbg_take_hint (sbg_engine_t *a_engine, int a_kind, const char *a_uri) {
    char *l_uri = sbg_normalized_uri (a_uri);
    gint64 l_now = g_get_monotonic_time ();
    int i, l_found = -1;
    for (i = 0; i < SBG_MAX_HINTS; i++) {
        if (a_engine->hints[i].uri && l_now - a_engine->hints[i].at > SBG_HINT_LIFE_US) {
            g_free (a_engine->hints[i].uri);
            a_engine->hints[i].uri = NULL;
        }
        if (a_engine->hints[i].uri && a_engine->hints[i].kind == a_kind && strcmp (a_engine->hints[i].uri, l_uri) == 0
                && (l_found < 0 || a_engine->hints[i].at < a_engine->hints[l_found].at)) {
            l_found = i;
        }
    }
    g_free (l_uri);
    if (l_found >= 0) {
        g_free (a_engine->hints[l_found].uri);
        a_engine->hints[l_found].uri = NULL;
        return 1;
    }
    return 0;
}

/* The held entry of decision `a_number' of engine `a_engine', or NULL. */
static sbg_held_t *sbg_held_entry (int a_engine, int a_number) {
    int i;
    for (i = 0; i < SBG_MAX_HELD; i++) {
        if (sbg_held[i].in_use && sbg_held[i].engine == a_engine && sbg_held[i].number == a_number) {
            return &sbg_held[i];
        }
    }
    return NULL;
}

/* Hold `a_decision' for engine `a_engine' under a new decision number; 0 if there is no room. */
static int sbg_hold (int a_engine, WebKitPolicyDecision *a_decision, int a_kind, const char *a_uri,
                     const char *a_method, int a_echo) {
    int i;
    for (i = 0; i < SBG_MAX_HELD; i++) {
        if (!sbg_held[i].in_use) {
            sbg_next_decision = sbg_next_decision + 1;
            if (sbg_next_decision <= 0) { sbg_next_decision = 1; }
            sbg_held[i].in_use = 1;
            sbg_held[i].engine = a_engine;
            sbg_held[i].number = sbg_next_decision;
            sbg_held[i].decision = g_object_ref (a_decision);
            sbg_held[i].kind = a_kind;
            sbg_held[i].uri = g_strdup (a_uri ? a_uri : "");
            sbg_held[i].method = g_strdup (a_method ? a_method : "GET");
            sbg_held[i].echo = a_echo;
            return sbg_next_decision;
        }
    }
    return 0;
}

/* Release held entry `a_held' (its decision already answered). */
static void sbg_release_held (sbg_held_t *a_held) {
    g_object_unref (a_held->decision);
    g_free (a_held->uri);
    g_free (a_held->method);
    memset (a_held, 0, sizeof (sbg_held_t));
}

static void sbg_set_pass (sbg_engine_t *a_engine, const char *a_uri);

/* `a_text' with HTML's special characters escaped; g_free it. */
static char *sbg_html_text (const char *a_text) {
    return g_markup_escape_text (a_text ? a_text : "", -1);
}

/* Is `a_uri' the URL `test_echo_at' answers? */
static int sbg_is_echo (sbg_engine_t *a_engine, const char *a_uri) {
    char *l_uri;
    int l_result = 0;
    if (a_engine->echo_url && a_uri) {
        l_uri = sbg_normalized_uri (a_uri);
        l_result = strcmp (l_uri, a_engine->echo_url) == 0;
        g_free (l_uri);
    }
    return l_result;
}

/* Answer the request for the echo URL `a_uri' with the echo page: its element `echo' shows the
   method, a line break, then the body. WebKitGTK 6.0 (2.52) gives a navigation's request its
   method and headers but no body (WebKitURIRequest has no body; https cannot take a URI scheme
   handler), so the body shown is empty. */
static void sbg_answer_echo (sbg_engine_t *a_engine, const char *a_uri, const char *a_method) {
    char *l_method = sbg_html_text (a_method ? a_method : "GET");
    char *l_page = g_strdup_printf ("<html><head><title>echo</title></head><body><pre id=\"echo\">%s\n</pre></body></html>", l_method);
    sbg_log ("echo uri=%.200s method=%s (no body: WebKitGTK does not expose it)", a_uri, a_method ? a_method : "");
    sbg_set_pass (a_engine, a_uri);
    webkit_web_view_load_html (a_engine->view, l_page, a_uri);
    g_free (l_page);
    g_free (l_method);
}

/* Answer held decision `a_number' of engine `a_engine': use it if `a_allow', else ignore it. */
static void sbg_decide (int a_engine, int a_number, int a_allow) {
    sbg_engine_t *l_engine = sbg_engine (a_engine);
    sbg_held_t *l_held = sbg_held_entry (a_engine, a_number);
    if (!l_held) { return; }
    sbg_log ("decide engine=%d number=%d allow=%d", a_engine, a_number, a_allow);
    if (a_allow && l_engine && !l_engine->disposing) {
        if (l_held->echo) {
            webkit_policy_decision_ignore (l_held->decision);
            sbg_answer_echo (l_engine, l_held->uri, l_held->method);
        } else {
            l_engine->pass_active = 1;
            webkit_policy_decision_use (l_held->decision);
        }
    } else {
        webkit_policy_decision_ignore (l_held->decision);
    }
    sbg_release_held (l_held);
}

/* Ignore and release every decision engine `a_engine' holds. */
static void sbg_ignore_held (int a_engine) {
    int i;
    for (i = 0; i < SBG_MAX_HELD; i++) {
        if (sbg_held[i].in_use && sbg_held[i].engine == a_engine) {
            webkit_policy_decision_ignore (sbg_held[i].decision);
            sbg_release_held (&sbg_held[i]);
        }
    }
}

/* BROWSER_ENGINE's kind of a WebKit navigation type. */
static int sbg_navigation_kind (WebKitNavigationType a_type) {
    switch (a_type) {
    case WEBKIT_NAVIGATION_TYPE_LINK_CLICKED: return 1;
    case WEBKIT_NAVIGATION_TYPE_FORM_SUBMITTED: return 2;
    case WEBKIT_NAVIGATION_TYPE_FORM_RESUBMITTED: return 2;
    case WEBKIT_NAVIGATION_TYPE_BACK_FORWARD: return 3;
    case WEBKIT_NAVIGATION_TYPE_RELOAD: return 4;
    default: return 0;
    }
}

/* The URI of `a_action''s request, or "". */
static const char *sbg_action_uri (WebKitNavigationAction *a_action) {
    WebKitURIRequest *l_request = a_action ? webkit_navigation_action_get_request (a_action) : NULL;
    const char *l_uri = l_request ? webkit_uri_request_get_uri (l_request) : NULL;
    return l_uri ? l_uri : "";
}

/* Is `a_uri' the program's own load, still to let through? Consumes the pass if so. */
static int sbg_take_pass (sbg_engine_t *a_engine, const char *a_uri) {
    char *l_uri;
    int l_result = 0;
    if (a_engine->pass_url) {
        l_uri = sbg_normalized_uri (a_uri);
        l_result = (strcmp (a_engine->pass_url, a_uri) == 0) || (l_uri && strcmp (a_engine->pass_url, l_uri) == 0);
        g_free (l_uri);
        if (l_result) {
            g_free (a_engine->pass_url);
            a_engine->pass_url = NULL;
            a_engine->pass_active = 1;
        }
    }
    return l_result;
}

/* Let held decision `a_held' through without asking: an iframe's navigation its parent started. */
static void sbg_let_through (sbg_engine_t *a_engine, sbg_held_t *a_held) {
    sbg_log ("not asked (the parent set an iframe's src) uri=%.200s", a_held->uri);
    if (a_held->echo) {
        webkit_policy_decision_ignore (a_held->decision);
        sbg_answer_echo (a_engine, a_held->uri, a_held->method);
    } else {
        webkit_policy_decision_use (a_held->decision);
    }
    sbg_release_held (a_held);
}

/* The page's answer about a held navigation that had no hint: for type OTHER, is its URL the
   src of an iframe on the page (one the parser or innerHTML made, loading its first document)?
   Then, or with a parent's hint that came meanwhile, it is the parent's, not asked; with a
   frame's own hint that came meanwhile it is asked as an iframe's; else as the main frame's. */
static void sbg_on_classified (GObject *a_view, GAsyncResult *a_result, gpointer a_data) {
    sbg_evaluation_t *l_query = (sbg_evaluation_t *) a_data;
    sbg_engine_t *l_engine = sbg_engine (l_query->engine);
    GError *l_error = NULL;
    JSCValue *l_value;
    sbg_held_t *l_held;
    int l_is_src = 0;
    l_value = webkit_web_view_evaluate_javascript_finish (WEBKIT_WEB_VIEW (a_view), a_result, &l_error);
    if (l_value) {
        l_is_src = jsc_value_is_boolean (l_value) && jsc_value_to_boolean (l_value);
        g_object_unref (l_value);
    }
    if (l_error) { g_error_free (l_error); }
    if (l_engine && !l_engine->disposing && l_engine->serial == l_query->serial) {
        l_held = sbg_held_entry (l_query->engine, l_query->ticket);
        if (l_held) {
            if (l_is_src || sbg_take_hint (l_engine, SBG_HINT_PARENT, l_held->uri)) {
                sbg_take_hint (l_engine, SBG_HINT_FRAME, l_held->uri);
                sbg_let_through (l_engine, l_held);
            } else {
                sbg_push (l_query->engine, SBG_EVENT_NAVIGATING, l_held->number, l_held->kind,
                          sbg_take_hint (l_engine, SBG_HINT_FRAME, l_held->uri) ? 0 : 1, l_held->uri, NULL, NULL);
            }
        }
    }
    g_free (l_query);
}

/* decide-policy: navigation actions are held for Eiffel while deciding; new-window actions
   are ignored and reported; responses keep WebKit's default.

   Which frame: WebKitGTK 6.0's navigation action has no frame and no source frame. Its frame
   name is the target frame's name (a link's target), measured NULL for the main frame and for
   unnamed and named iframes alike; the request's headers do not differ either. So the
   engine's frame script (`Sbg_frame_script', every frame) tells the UI process first, on its
   own channel: a frame starting a navigation of its own (a link or a form in it) and a page
   setting an iframe's src. A hint can come just after the policy request, so a navigation
   without one waits for one round trip to the page (sbg_on_classified) before it is told.
   - about:srcdoc, or a parent's hint: an iframe navigation its parent started, not asked;
   - type OTHER whose URL is the src of an iframe on the page (the parser's): the same;
   - a frame's own hint: asked, not in the main frame;
   - otherwise: the main frame's, asked. An iframe's script setting its own location gives
     no hint (Location cannot be wrapped), so it is reported as the main frame's. */
static gboolean sbg_on_decide_policy (WebKitWebView *a_view, WebKitPolicyDecision *a_decision,
                                      WebKitPolicyDecisionType a_type, gpointer a_data) {
    sbg_engine_t *l_engine = sbg_live (a_data);
    int l_id = GPOINTER_TO_INT (a_data);
    WebKitNavigationAction *l_action;
    WebKitNavigationType l_type;
    const char *l_uri, *l_method;
    char *l_json, *l_script;
    sbg_evaluation_t *l_query;
    int l_number, l_kind, l_echo;
    if (!l_engine) { return FALSE; }
    if (a_type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION) {
        l_action = webkit_navigation_policy_decision_get_navigation_action (WEBKIT_NAVIGATION_POLICY_DECISION (a_decision));
        l_uri = sbg_action_uri (l_action);
        l_type = webkit_navigation_action_get_navigation_type (l_action);
        l_method = webkit_uri_request_get_http_method (webkit_navigation_action_get_request (l_action));
        sbg_log ("decide-policy navigation engine=%d type=%d method=%s gesture=%d redirect=%d pass=%s deciding=%d uri=%.200s",
                 l_id, (int) l_type, l_method ? l_method : "-",
                 (int) webkit_navigation_action_is_user_gesture (l_action),
                 (int) webkit_navigation_action_is_redirect (l_action),
                 l_engine->pass_url ? l_engine->pass_url : "-", l_engine->deciding, l_uri);
        if (sbg_take_pass (l_engine, l_uri)) {
            return FALSE;   /* the program's own navigate or set_html: never asked (4.4) */
        }
        if (l_engine->pass_active && webkit_navigation_action_is_redirect (l_action)) {
            return FALSE;   /* a redirect of a load already let through */
        }
        l_echo = sbg_is_echo (l_engine, l_uri);
        if (!l_engine->deciding) {
            if (l_echo) {
                webkit_policy_decision_ignore (a_decision);
                sbg_answer_echo (l_engine, l_uri, l_method);
                return TRUE;
            }
            return FALSE;   /* no handler: WebKit's default, allow, with no event */
        }
        if (strcmp (l_uri, "about:srcdoc") == 0) {
            return FALSE;   /* an iframe's srcdoc: its parent's navigation, not asked */
        }
        l_kind = sbg_navigation_kind (l_type);
        l_number = sbg_hold (l_id, a_decision, l_kind, l_uri, l_method, l_echo);
        if (l_number == 0) {
            return FALSE;   /* no room to hold it: allowed, as with no handler */
        }
        if (sbg_take_hint (l_engine, SBG_HINT_PARENT, l_uri)) {
            sbg_take_hint (l_engine, SBG_HINT_FRAME, l_uri);
            sbg_let_through (l_engine, sbg_held_entry (l_id, l_number));
        } else if (sbg_take_hint (l_engine, SBG_HINT_FRAME, l_uri)) {
            sbg_push (l_id, SBG_EVENT_NAVIGATING, l_number, l_kind, 0, l_uri, NULL, NULL);
        } else if (l_engine->has_page) {
            l_json = sbg_json_string (l_uri);
            l_script = g_strdup_printf ("%s && (typeof window.__sb_gtk_is_frame_src === \"function\") && window.__sb_gtk_is_frame_src (%s)",
                                        l_type == WEBKIT_NAVIGATION_TYPE_OTHER ? "true" : "false", l_json);
            l_query = g_new0 (sbg_evaluation_t, 1);
            l_query->engine = l_id;
            l_query->serial = l_engine->serial;
            l_query->ticket = l_number;
            webkit_web_view_evaluate_javascript (l_engine->view, l_script, -1, NULL, NULL, l_engine->cancellable,
                                                 sbg_on_classified, l_query);
            g_free (l_script);
            g_free (l_json);
        } else {
            sbg_push (l_id, SBG_EVENT_NAVIGATING, l_number, l_kind, 1, l_uri, NULL, NULL);
        }
        return TRUE;
    } else if (a_type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
        l_action = webkit_navigation_policy_decision_get_navigation_action (WEBKIT_NAVIGATION_POLICY_DECISION (a_decision));
        l_uri = sbg_action_uri (l_action);
        sbg_log ("decide-policy new window engine=%d uri=%.200s", l_id, l_uri);
        webkit_policy_decision_ignore (a_decision);
        sbg_push (l_id, SBG_EVENT_NEW_WINDOW, 0, 0, 0, l_uri, NULL, NULL);
        return TRUE;
    }
    return FALSE;
}

/* create: nothing opens on its own. A new window that reached here without a NEW_WINDOW_ACTION
   decision (window.open) is reported here. */
static GtkWidget *sbg_on_create (WebKitWebView *a_view, WebKitNavigationAction *a_action, gpointer a_data) {
    sbg_engine_t *l_engine = sbg_live (a_data);
    const char *l_uri = sbg_action_uri (a_action);
    sbg_log ("create engine=%d uri=%.200s", GPOINTER_TO_INT (a_data), l_uri);
    if (l_engine) {
        sbg_push (GPOINTER_TO_INT (a_data), SBG_EVENT_NEW_WINDOW, 0, 0, 0, l_uri, NULL, NULL);
    }
    return NULL;
}

/* ------------------------------------------------------------------------------------------ */
/* Title, loads, messages, closing                                                            */
/* ------------------------------------------------------------------------------------------ */

static void sbg_on_title (GObject *a_view, GParamSpec *a_spec, gpointer a_data) {
    const char *l_title;
    if (sbg_live (a_data)) {
        l_title = webkit_web_view_get_title (WEBKIT_WEB_VIEW (a_view));
        sbg_push (GPOINTER_TO_INT (a_data), SBG_EVENT_TITLE, 0, 0, 0, l_title ? l_title : "", NULL, NULL);
    }
}

static void sbg_on_load_changed (WebKitWebView *a_view, WebKitLoadEvent a_event, gpointer a_data) {
    sbg_engine_t *l_engine = sbg_live (a_data);
    if (!l_engine) { return; }
    sbg_log ("load-changed engine=%d event=%d failed=%d uri=%.200s", GPOINTER_TO_INT (a_data), (int) a_event,
             l_engine->load_failed, webkit_web_view_get_uri (a_view) ? webkit_web_view_get_uri (a_view) : "");
    switch (a_event) {
    case WEBKIT_LOAD_STARTED:
        l_engine->load_failed = 0;
        l_engine->has_page = 1;
        break;
    case WEBKIT_LOAD_COMMITTED:
            /* The policy checks of this load are over: a pass not taken goes. */
        g_free (l_engine->pass_url);
        l_engine->pass_url = NULL;
        l_engine->pass_active = 0;
        break;
    case WEBKIT_LOAD_FINISHED:
        if (!l_engine->load_failed) {
            sbg_push (GPOINTER_TO_INT (a_data), SBG_EVENT_LOADED, 0, 0, 0, "", NULL, NULL);
        }
        l_engine->load_failed = 0;
        l_engine->pass_active = 0;
        break;
    default:
        break;
    }
}

static gboolean sbg_on_load_failed (WebKitWebView *a_view, WebKitLoadEvent a_event, const char *a_uri,
                                    GError *a_error, gpointer a_data) {
    sbg_engine_t *l_engine = sbg_live (a_data);
    if (!l_engine) { return TRUE; }
    sbg_log ("load-failed engine=%d event=%d error=%s uri=%.200s", GPOINTER_TO_INT (a_data), (int) a_event,
             a_error ? a_error->message : "", a_uri ? a_uri : "");
    l_engine->load_failed = 1;
    l_engine->pass_active = 0;
    if (a_error && (g_error_matches (a_error, WEBKIT_NETWORK_ERROR, WEBKIT_NETWORK_ERROR_CANCELLED)
            || g_error_matches (a_error, WEBKIT_POLICY_ERROR, WEBKIT_POLICY_ERROR_FRAME_LOAD_INTERRUPTED_BY_POLICY_CHANGE))) {
        return TRUE;   /* our own cancel, or a navigation ignored: nothing to report */
    }
    sbg_push (GPOINTER_TO_INT (a_data), SBG_EVENT_LOADED, 1, 0, 0,
              (a_error && a_error->message) ? a_error->message : "load failed", NULL, NULL);
    return TRUE;   /* no error page of WebKit's own: it would be a load of its own */
}

/* The text of property `a_name' of the JavaScript object `a_value'; g_free it. */
static char *sbg_property_text (JSCValue *a_value, const char *a_name) {
    JSCValue *l_property = jsc_value_object_get_property (a_value, a_name);
    char *l_result = NULL;
    if (l_property) {
        if (!jsc_value_is_undefined (l_property) && !jsc_value_is_null (l_property)) {
            l_result = jsc_value_to_string (l_property);
        }
        g_object_unref (l_property);
    }
    return l_result ? l_result : g_strdup ("");
}

/* script-message-received::sb: the bridge's {name, seq, args}, `args' already JSON text. */
static void sbg_on_message (WebKitUserContentManager *a_manager, JSCValue *a_value, gpointer a_data) {
    char *l_name, *l_seq, *l_args;
    if (!sbg_live (a_data) || !a_value || !jsc_value_is_object (a_value)) { return; }
    l_name = sbg_property_text (a_value, "name");
    l_seq = sbg_property_text (a_value, "seq");
    l_args = sbg_property_text (a_value, "args");
    if (l_name[0] && l_seq[0]) {
        sbg_push (GPOINTER_TO_INT (a_data), SBG_EVENT_CALL, 0, 0, 0, l_name, l_seq, l_args[0] ? l_args : "[]");
    }
    g_free (l_name);
    g_free (l_seq);
    g_free (l_args);
}

/* The engine's own script, at the start of every document in every frame, in the page's world:
   it tells the UI process, on the channel sb_gtk_frame and ahead of WebKit's policy request
   (the same connection, in order), what decide-policy cannot see (sbg_on_decide_policy):
   - in an iframe, each link click and form submission it starts in itself, as {frame: url}
     (sent as the click or submit event ends, before the navigation starts: the Navigation
     API's navigate event was measured to fire only after the policy decision);
   - in any page, an iframe's src set by script (the src property, setAttribute) as {parent: url};
   - `__sb_gtk_is_frame_src (url)': is `url' the src of an iframe in this page (or in a
     same-origin iframe inside it)? */
static const char *Sbg_frame_script =
"(() => {\n"
"  if (window.__sb_gtk_frames) { return; }\n"
"  Object.defineProperty (window, \"__sb_gtk_frames\", {value: true});\n"
"  const post = (message) => {\n"
"    try { window.webkit.messageHandlers.sb_gtk_frame.postMessage (message); } catch (e) { }\n"
"  };\n"
"  const absolute = (url) => { try { return new URL (String (url), document.baseURI).href; } catch (e) { return String (url); } };\n"
"  if (window !== window.top) {\n"
"    const own = (target) => { const t = String (target || \"\"); return t === \"\" || t === \"_self\"; };\n"
"    window.addEventListener (\"click\", (event) => {\n"
"      const link = event.target && event.target.closest ? event.target.closest (\"a[href]\") : null;\n"
"      if (link && !event.defaultPrevented && own (link.target)) { post ({frame: link.href}); }\n"
"    });\n"
"    const form_url = (form, submitter) => {\n"
"      const action = (submitter && submitter.hasAttribute (\"formaction\")) ? submitter.formAction : form.action;\n"
"      const method = String ((submitter && submitter.hasAttribute (\"formmethod\") && submitter.formMethod) || form.method || \"get\").toLowerCase ();\n"
"      if (method !== \"get\") { return action; }\n"
"      const url = new URL (action);\n"
"      url.search = new URLSearchParams (submitter ? new FormData (form, submitter) : new FormData (form)).toString ();\n"
"      return url.href;\n"
"    };\n"
"    window.addEventListener (\"submit\", (event) => {\n"
"      const form = event.target;\n"
"      if (!event.defaultPrevented && form && own ((event.submitter && event.submitter.formTarget) || form.target)) {\n"
"        try { post ({frame: form_url (form, event.submitter || null)}); } catch (e) { }\n"
"      }\n"
"    });\n"
"  }\n"
"  const told = (element, value) => {\n"
"    if (element instanceof HTMLIFrameElement) { post ({parent: absolute (value)}); }\n"
"  };\n"
"  const source = Object.getOwnPropertyDescriptor (HTMLIFrameElement.prototype, \"src\");\n"
"  if (source && source.set) {\n"
"    Object.defineProperty (HTMLIFrameElement.prototype, \"src\", {configurable: true, enumerable: source.enumerable,\n"
"      get: source.get, set (value) { told (this, value); source.set.call (this, value); }});\n"
"  }\n"
"  const set_attribute = Element.prototype.setAttribute;\n"
"  Element.prototype.setAttribute = function (name, value) {\n"
"    if (String (name).toLowerCase () === \"src\") { told (this, value); }\n"
"    return set_attribute.call (this, name, value);\n"
"  };\n"
"  const is_src = (doc, url) => {\n"
"    for (const element of doc.querySelectorAll (\"iframe, frame\")) {\n"
"      if (element.src === url) { return true; }\n"
"      let inner = null;\n"
"      try { inner = element.contentDocument; } catch (e) { }\n"
"      if (inner && is_src (inner, url)) { return true; }\n"
"    }\n"
"    return false;\n"
"  };\n"
"  Object.defineProperty (window, \"__sb_gtk_is_frame_src\", {value: (url) => is_src (document, url)});\n"
"}) ();\n";

/* sb_gtk_frame: the frame script's {frame: url} or {parent: url}. */
static void sbg_on_frame_hint (WebKitUserContentManager *a_manager, JSCValue *a_value, gpointer a_data) {
    sbg_engine_t *l_engine = sbg_live (a_data);
    char *l_url;
    if (!l_engine || !a_value || !jsc_value_is_object (a_value)) { return; }
    if (jsc_value_object_has_property (a_value, "frame")) {
        l_url = sbg_property_text (a_value, "frame");
        sbg_log ("hint frame engine=%d url=%.200s", GPOINTER_TO_INT (a_data), l_url);
        if (l_url[0]) { sbg_add_hint (l_engine, SBG_HINT_FRAME, l_url); }
        g_free (l_url);
    } else if (jsc_value_object_has_property (a_value, "parent")) {
        l_url = sbg_property_text (a_value, "parent");
        sbg_log ("hint parent engine=%d url=%.200s", GPOINTER_TO_INT (a_data), l_url);
        if (l_url[0]) { sbg_add_hint (l_engine, SBG_HINT_PARENT, l_url); }
        g_free (l_url);
    }
}

/* close-request: queue `closed' and keep the window; `dispose' destroys it. */
static gboolean sbg_on_close_request (GtkWindow *a_window, gpointer a_data) {
    sbg_engine_t *l_engine = sbg_live (a_data);
    if (l_engine && !l_engine->closed) {
        l_engine->closed = 1;
        sbg_push (GPOINTER_TO_INT (a_data), SBG_EVENT_CLOSED, 0, 0, 0, NULL, NULL, NULL);
    }
    return TRUE;
}

/* ------------------------------------------------------------------------------------------ */
/* Scripts                                                                                    */
/* ------------------------------------------------------------------------------------------ */

/* Run `a_script' on the page shown now, if there is one; its result is discarded. */
static void sbg_eval (int a_id, const char *a_script) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    if (l_engine && l_engine->view && l_engine->has_page && a_script) {
        webkit_web_view_evaluate_javascript (l_engine->view, a_script, -1, NULL, NULL, NULL, NULL, NULL);
    }
}

/* Give the content manager every kept script again, in the order they were added. */
static void sbg_reload_scripts (sbg_engine_t *a_engine) {
    WebKitUserScript *l_script;
    int i;
    webkit_user_content_manager_remove_all_scripts (a_engine->content_manager);
    for (i = 0; i < SBG_MAX_SCRIPTS; i++) {
        if (a_engine->scripts[i].in_use) {
            l_script = webkit_user_script_new (a_engine->scripts[i].source,
                a_engine->scripts[i].all_frames ? WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES : WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
                WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, NULL, NULL);
            webkit_user_content_manager_add_script (a_engine->content_manager, l_script);
            webkit_user_script_unref (l_script);
        }
    }
}

/* Run `a_script' at the start of every page (document start; in every frame if `a_all_frames',
   else in the top frame), kept under `a_name' (NULL or empty for a script kept for good), and on
   the page shown now if `a_now'. */
static void sbg_add_script (int a_id, const char *a_name, const char *a_script, int a_now, int a_all_frames) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    WebKitUserScript *l_script;
    int i, l_slot = -1;
    if (!l_engine || !l_engine->content_manager || !a_script) { return; }
    for (i = SBG_MAX_SCRIPTS - 1; i >= 0; i--) {
        if (!l_engine->scripts[i].in_use) { l_slot = i; } else { break; }
    }
    if (l_slot < 0) {
            /* The slots after the last one used are full: compact, keeping the order. */
        int l_to = 0;
        for (i = 0; i < SBG_MAX_SCRIPTS; i++) {
            if (l_engine->scripts[i].in_use) {
                if (i != l_to) { l_engine->scripts[l_to] = l_engine->scripts[i]; memset (&l_engine->scripts[i], 0, sizeof (sbg_script_t)); }
                l_to = l_to + 1;
            }
        }
        if (l_to >= SBG_MAX_SCRIPTS) { return; }
        l_slot = l_to;
    }
    l_engine->scripts[l_slot].in_use = 1;
    l_engine->scripts[l_slot].name = (a_name && a_name[0]) ? g_strdup (a_name) : NULL;
    l_engine->scripts[l_slot].source = g_strdup (a_script);
    l_engine->scripts[l_slot].all_frames = a_all_frames;
    l_script = webkit_user_script_new (a_script,
        a_all_frames ? WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES : WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
        WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, NULL, NULL);
    webkit_user_content_manager_add_script (l_engine->content_manager, l_script);
    webkit_user_script_unref (l_script);
    if (a_now) { sbg_eval (a_id, a_script); }
}

/* Stop running the scripts kept under `a_name' on new pages. WebKitUserContentManager cannot
   remove one script, so every script goes and the rest come back. */
static void sbg_remove_script (int a_id, const char *a_name) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    int i, l_found = 0;
    if (!l_engine || !a_name || !a_name[0]) { return; }
    for (i = 0; i < SBG_MAX_SCRIPTS; i++) {
        if (l_engine->scripts[i].in_use && l_engine->scripts[i].name && strcmp (l_engine->scripts[i].name, a_name) == 0) {
            g_free (l_engine->scripts[i].name);
            g_free (l_engine->scripts[i].source);
            memset (&l_engine->scripts[i], 0, sizeof (sbg_script_t));
            l_found = 1;
        }
    }
    if (l_found) { sbg_reload_scripts (l_engine); }
}

static void sbg_on_evaluated (GObject *a_view, GAsyncResult *a_result, gpointer a_data) {
    sbg_evaluation_t *l_evaluation = (sbg_evaluation_t *) a_data;
    sbg_engine_t *l_engine = sbg_engine (l_evaluation->engine);
    GError *l_error = NULL;
    JSCValue *l_value;
    char *l_text;
    l_value = webkit_web_view_call_async_javascript_function_finish (WEBKIT_WEB_VIEW (a_view), a_result, &l_error);
    if (l_engine && !l_engine->disposing && l_engine->serial == l_evaluation->serial) {
        if (l_value) {
            l_text = jsc_value_is_string (l_value) ? jsc_value_to_string (l_value) : g_strdup ("null");
            sbg_push (l_evaluation->engine, SBG_EVENT_EVALUATED, l_evaluation->ticket, 0, 0, l_text, NULL, NULL);
            g_free (l_text);
        } else {
            l_text = sbg_json_string ((l_error && l_error->message) ? l_error->message : "the script failed");
            sbg_push (l_evaluation->engine, SBG_EVENT_EVALUATED, l_evaluation->ticket, 1, 0, l_text, NULL, NULL);
            g_free (l_text);
        }
    }
    if (l_value) { g_object_unref (l_value); }
    if (l_error) { g_error_free (l_error); }
    g_free (l_evaluation);
}

/* Run the async function body `a_body' (shared code's evaluate wrapper) in the page's world;
   its string comes back as an `evaluated' event with `a_ticket'. */
static void sbg_evaluate (int a_id, int a_ticket, const char *a_body) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    sbg_evaluation_t *l_evaluation;
    char *l_text;
    if (!l_engine || !l_engine->view) { return; }
    if (!l_engine->has_page) {
        l_text = sbg_json_string ("no page is loaded");
        sbg_push (a_id, SBG_EVENT_EVALUATED, a_ticket, 1, 0, l_text, NULL, NULL);
        g_free (l_text);
        return;
    }
    l_evaluation = g_new0 (sbg_evaluation_t, 1);
    l_evaluation->engine = a_id;
    l_evaluation->serial = l_engine->serial;
    l_evaluation->ticket = a_ticket;
    webkit_web_view_call_async_javascript_function (l_engine->view, a_body, -1, NULL, NULL, NULL,
                                                    l_engine->cancellable, sbg_on_evaluated, l_evaluation);
}

/* ------------------------------------------------------------------------------------------ */
/* Navigation                                                                                 */
/* ------------------------------------------------------------------------------------------ */

/* Let the next navigation of `a_uri' through: the program's own load. */
static void sbg_set_pass (sbg_engine_t *a_engine, const char *a_uri) {
    g_free (a_engine->pass_url);
    a_engine->pass_url = sbg_normalized_uri (a_uri);
    a_engine->has_page = 1;
}

static void sbg_navigate (int a_id, const char *a_url) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    if (!l_engine || !l_engine->view || !a_url) { return; }
    sbg_set_pass (l_engine, a_url);
    webkit_web_view_load_uri (l_engine->view, a_url);
}

/* Load `a_html' as the document at `a_base'. */
static void sbg_set_html_with_base (int a_id, const char *a_html, const char *a_base) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    if (!l_engine || !l_engine->view || !a_html || !a_base) { return; }
    sbg_set_pass (l_engine, a_base);
    webkit_web_view_load_html (l_engine->view, a_html, a_base);
}

/* Test hook: answer every request for `a_url' with the echo page (sbg_answer_echo). */
static void sbg_set_echo (int a_id, const char *a_url) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    if (!l_engine || !a_url) { return; }
    g_free (l_engine->echo_url);
    l_engine->echo_url = sbg_normalized_uri (a_url);
}

static void sbg_set_deciding (int a_id, int a_on) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    if (l_engine) { l_engine->deciding = a_on; }
}

static void sbg_set_dev_tools (int a_id, int a_on) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    if (l_engine && l_engine->view) {
        webkit_settings_set_enable_developer_extras (webkit_web_view_get_settings (l_engine->view), a_on ? TRUE : FALSE);
    }
}

/* ------------------------------------------------------------------------------------------ */
/* The window                                                                                 */
/* ------------------------------------------------------------------------------------------ */

static void sbg_set_title (int a_id, const char *a_title) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    if (l_engine && l_engine->owns_window && l_engine->window) {
        gtk_window_set_title (GTK_WINDOW (l_engine->window), a_title ? a_title : "");
    }
}

/* The content's size now, laid out (0 before it is), logical pixels: `a_height' 0 width. */
static int sbg_content_size (int a_id, int a_height) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    GtkWidget *l_content;
    if (!l_engine) { return 0; }
    l_content = l_engine->owns_window ? l_engine->content : GTK_WIDGET (l_engine->view);
    if (!l_content) { return 0; }
    return a_height ? gtk_widget_get_height (l_content) : gtk_widget_get_width (l_content);
}

/* Size the own window's content to `a_width' by `a_height', clamped by the hints. GTK 4 has no
   maximum size: a max hint clamps the program's own sizes only (spec 4.8). */
static void sbg_apply_size (sbg_engine_t *a_engine, int a_width, int a_height) {
    if (!a_engine->owns_window || !a_engine->window) { return; }
    if (a_engine->min_w > 0 && a_width < a_engine->min_w) { a_width = a_engine->min_w; }
    if (a_engine->min_h > 0 && a_height < a_engine->min_h) { a_height = a_engine->min_h; }
    if (a_engine->max_w > 0 && a_width > a_engine->max_w) { a_width = a_engine->max_w; }
    if (a_engine->max_h > 0 && a_height > a_engine->max_h) { a_height = a_engine->max_h; }
    a_engine->width = a_width;
    a_engine->height = a_height;
    gtk_window_set_default_size (GTK_WINDOW (a_engine->window), a_width, a_height);
}

/* The size the content has, if laid out, else the size last asked for. */
static void sbg_current_size (sbg_engine_t *a_engine, int a_id, int *a_width, int *a_height) {
    int l_width = sbg_content_size (a_id, 0), l_height = sbg_content_size (a_id, 1);
    *a_width = l_width > 0 ? l_width : a_engine->width;
    *a_height = l_height > 0 ? l_height : a_engine->height;
}

/* The minimum the view asks of the window: the min hint, or none. */
static void sbg_set_minimum (sbg_engine_t *a_engine, int a_width, int a_height) {
    if (a_width > 0 && a_height > 0) {
        gtk_widget_set_size_request (GTK_WIDGET (a_engine->view), a_width, a_height);
    } else {
        gtk_widget_set_size_request (GTK_WIDGET (a_engine->view), -1, -1);
    }
}

/* Size hints: 0 none, 1 min, 2 max, 3 fixed. A hint holds against later sizes. */
static void sbg_set_size (int a_id, int a_width, int a_height, int a_hint) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    int l_width, l_height;
    if (!l_engine || !l_engine->owns_window || !l_engine->window) { return; }
    switch (a_hint) {
    case 1:
        if (l_engine->fixed) {
            l_engine->fixed = 0;
            l_engine->max_w = 0;
            l_engine->max_h = 0;
            gtk_window_set_resizable (GTK_WINDOW (l_engine->window), TRUE);
        }
        l_engine->min_w = a_width;
        l_engine->min_h = a_height;
        if (l_engine->max_w > 0 && (l_engine->max_w < a_width || l_engine->max_h < a_height)) {
            l_engine->max_w = 0;
            l_engine->max_h = 0;
        }
        sbg_set_minimum (l_engine, a_width, a_height);
        sbg_current_size (l_engine, a_id, &l_width, &l_height);
        sbg_apply_size (l_engine, l_width, l_height);
        break;
    case 2:
        if (l_engine->fixed) {
            l_engine->fixed = 0;
            l_engine->min_w = 0;
            l_engine->min_h = 0;
            sbg_set_minimum (l_engine, 0, 0);
            gtk_window_set_resizable (GTK_WINDOW (l_engine->window), TRUE);
        }
        l_engine->max_w = a_width;
        l_engine->max_h = a_height;
        if (l_engine->min_w > 0 && (l_engine->min_w > a_width || l_engine->min_h > a_height)) {
            l_engine->min_w = 0;
            l_engine->min_h = 0;
            sbg_set_minimum (l_engine, 0, 0);
        }
        sbg_current_size (l_engine, a_id, &l_width, &l_height);
        sbg_apply_size (l_engine, l_width, l_height);
        break;
    case 3:
        l_engine->fixed = 1;
        l_engine->min_w = a_width;
        l_engine->min_h = a_height;
        l_engine->max_w = a_width;
        l_engine->max_h = a_height;
        sbg_set_minimum (l_engine, a_width, a_height);
        gtk_window_set_resizable (GTK_WINDOW (l_engine->window), FALSE);
        sbg_apply_size (l_engine, a_width, a_height);
        break;
    default:
        sbg_apply_size (l_engine, a_width, a_height);
        break;
    }
}

/* Put the own window on screen without taking the focus. On X11 a user time of 0 asks the
   window manager not to focus it; GTK 4 has no such request on Wayland. */
static void sbg_show (int a_id) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    if (!l_engine || !l_engine->owns_window || !l_engine->window || gtk_widget_get_visible (l_engine->window)) { return; }
    gtk_widget_realize (l_engine->window);
#ifdef GDK_WINDOWING_X11
    {
        GdkSurface *l_surface = gtk_native_get_surface (GTK_NATIVE (l_engine->window));
        if (l_surface && GDK_IS_X11_SURFACE (l_surface)) {
            gdk_x11_surface_set_user_time (l_surface, 0);
        }
    }
#endif
    gtk_widget_set_visible (l_engine->window, TRUE);
}

static int sbg_is_resizable (int a_id) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    if (!l_engine || !l_engine->window || !GTK_IS_WINDOW (l_engine->window)) { return 0; }
    return gtk_window_get_resizable (GTK_WINDOW (l_engine->window)) ? 1 : 0;
}

/* Is `a_window' the own window of some live engine? */
static int sbg_is_engine_window (GtkWidget *a_window) {
    int i;
    for (i = 0; i < SBG_MAX_ENGINES; i++) {
        if (sbg_engines[i].in_use && sbg_engines[i].owns_window && sbg_engines[i].window == a_window) {
            return 1;
        }
    }
    return 0;
}

/* Does `a_widget' hold a WebKitWebView, at any depth? */
static int sbg_has_web_view (GtkWidget *a_widget) {
    GtkWidget *l_child;
    if (WEBKIT_IS_WEB_VIEW (a_widget)) { return 1; }
    for (l_child = gtk_widget_get_first_child (a_widget); l_child; l_child = gtk_widget_get_next_sibling (l_child)) {
        if (sbg_has_web_view (l_child)) { return 1; }
    }
    return 0;
}

/* Test hook: the engine's own window, if shown, plus every visible top-level window of this
   process that holds a web view no engine made (what a new-window request could add). Other
   engines' windows are left out. */
static int sbg_window_count (int a_id) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    GListModel *l_toplevels = gtk_window_get_toplevels ();
    GtkWidget *l_own = l_engine ? l_engine->window : NULL;
    GtkWidget *l_window;
    guint i, l_n = g_list_model_get_n_items (l_toplevels);
    int l_count = 0;
    for (i = 0; i < l_n; i++) {
        l_window = GTK_WIDGET (g_list_model_get_item (l_toplevels, i));
        if (gtk_widget_get_visible (l_window)) {
            if (l_window == l_own || (!sbg_is_engine_window (l_window) && sbg_has_web_view (l_window))) {
                l_count = l_count + 1;
            }
        }
        g_object_unref (l_window);
    }
    return l_count;
}

/* ------------------------------------------------------------------------------------------ */
/* The pump                                                                                   */
/* ------------------------------------------------------------------------------------------ */

static gboolean sbg_on_pump_timeout (gpointer a_data) {
    *((int *) a_data) = 1;
    return G_SOURCE_REMOVE;
}

/* Handle the default main context's sources for up to `a_ms' milliseconds, or until an event
   is queued for engine `a_id', or `sbg_wake' is called. */
static void sbg_pump (int a_id, int a_ms) {
    int l_expired = 0;
    GSource *l_timeout;
    while (g_main_context_iteration (NULL, FALSE)) {
        if (sbg_has_event (a_id)) { break; }
    }
    if (a_ms > 0 && !sbg_has_event (a_id) && !g_atomic_int_get (&sbg_wake_pending)) {
        l_timeout = g_timeout_source_new ((guint) a_ms);
        g_source_set_callback (l_timeout, sbg_on_pump_timeout, &l_expired, NULL);
        g_source_attach (l_timeout, NULL);
        while (!l_expired && !sbg_has_event (a_id) && !g_atomic_int_get (&sbg_wake_pending)) {
            g_main_context_iteration (NULL, TRUE);
        }
        g_source_destroy (l_timeout);
        g_source_unref (l_timeout);
    }
    g_atomic_int_set (&sbg_wake_pending, 0);
}

/* Wake `sbg_pump' if it waits (any thread). */
static void sbg_wake (void) {
    g_atomic_int_set (&sbg_wake_pending, 1);
    g_main_context_wakeup (NULL);
}

/* ------------------------------------------------------------------------------------------ */
/* Creation and disposal                                                                      */
/* ------------------------------------------------------------------------------------------ */

static int sbg_last_error (void) { return sbg_last_error_code; }

/* Make an engine: in a window of its own if `a_parent' is NULL, else inside `a_parent', a
   GtkWindow (the view becomes its child, or joins the GtkBox that is its child) or a GtkBox
   (the view is appended, expanding both ways). The id, or 0 (`sbg_last_error' says why). */
static int sbg_create (int a_ephemeral, int a_debug, void *a_parent) {
    sbg_engine_t *l_engine = NULL;
    GtkWidget *l_parent = (GtkWidget *) a_parent;
    GtkWidget *l_box = NULL, *l_child;
    GtkRoot *l_root;
    WebKitSettings *l_settings;
    unsigned int l_serial;
    int i, l_id = 0;
    gpointer l_data;
    if (sbg_gui_thread && g_thread_self () != sbg_gui_thread) {
        sbg_last_error_code = SBG_ERROR_NOT_GUI_THREAD;
        return 0;
    }
    if (!gtk_init_check ()) {
        sbg_last_error_code = SBG_ERROR_NO_DISPLAY;
        return 0;
    }
    if (!sbg_gui_thread) { sbg_gui_thread = g_thread_self (); }
    if (l_parent) {
        if (GTK_IS_WINDOW (l_parent)) {
            l_child = gtk_window_get_child (GTK_WINDOW (l_parent));
            if (l_child && GTK_IS_BOX (l_child)) {
                l_box = l_child;
            } else if (l_child) {
                sbg_last_error_code = SBG_ERROR_BAD_PARENT;
                return 0;
            }
        } else if (GTK_IS_BOX (l_parent)) {
            l_box = l_parent;
        } else {
            sbg_last_error_code = SBG_ERROR_BAD_PARENT;
            return 0;
        }
    }
    for (i = 0; i < SBG_MAX_ENGINES && !l_engine; i++) {
        if (!sbg_engines[i].in_use) {
            l_engine = &sbg_engines[i];
            l_id = i + 1;
        }
    }
    if (!l_engine) {
        sbg_last_error_code = SBG_ERROR_NO_ROOM;
        return 0;
    }
    l_serial = l_engine->serial + 1;
    memset (l_engine, 0, sizeof (sbg_engine_t));
    l_engine->serial = l_serial;
    l_engine->in_use = 1;
    l_engine->width = 800;
    l_engine->height = 600;
    l_data = GINT_TO_POINTER (l_id);

    l_engine->session = a_ephemeral ? webkit_network_session_new_ephemeral ()
                                    : g_object_ref (webkit_network_session_get_default ());
    l_engine->content_manager = webkit_user_content_manager_new ();
    webkit_user_content_manager_register_script_message_handler (l_engine->content_manager, "sb", NULL);
    webkit_user_content_manager_register_script_message_handler (l_engine->content_manager, "sb_gtk_frame", NULL);
    g_signal_connect (l_engine->content_manager, "script-message-received::sb", G_CALLBACK (sbg_on_message), l_data);
    g_signal_connect (l_engine->content_manager, "script-message-received::sb_gtk_frame", G_CALLBACK (sbg_on_frame_hint), l_data);
    sbg_add_script (l_id, NULL, Sbg_frame_script, 0, 1);
    l_engine->view = WEBKIT_WEB_VIEW (g_object_new (WEBKIT_TYPE_WEB_VIEW,
        "network-session", l_engine->session,
        "user-content-manager", l_engine->content_manager,
        NULL));
    g_object_ref_sink (l_engine->view);
    l_engine->cancellable = g_cancellable_new ();
    l_settings = webkit_web_view_get_settings (l_engine->view);
    webkit_settings_set_javascript_can_open_windows_automatically (l_settings, TRUE);
    webkit_settings_set_enable_developer_extras (l_settings, a_debug ? TRUE : FALSE);
    gtk_widget_set_hexpand (GTK_WIDGET (l_engine->view), TRUE);
    gtk_widget_set_vexpand (GTK_WIDGET (l_engine->view), TRUE);
    g_signal_connect (l_engine->view, "decide-policy", G_CALLBACK (sbg_on_decide_policy), l_data);
    g_signal_connect (l_engine->view, "create", G_CALLBACK (sbg_on_create), l_data);
    g_signal_connect (l_engine->view, "notify::title", G_CALLBACK (sbg_on_title), l_data);
    g_signal_connect (l_engine->view, "load-changed", G_CALLBACK (sbg_on_load_changed), l_data);
    g_signal_connect (l_engine->view, "load-failed", G_CALLBACK (sbg_on_load_failed), l_data);

    if (!l_parent) {
        l_engine->owns_window = 1;
        l_engine->window = gtk_window_new ();
        l_engine->content = gtk_box_new (GTK_ORIENTATION_VERTICAL, 0);
        gtk_box_append (GTK_BOX (l_engine->content), GTK_WIDGET (l_engine->view));
        gtk_window_set_child (GTK_WINDOW (l_engine->window), l_engine->content);
        gtk_window_set_default_size (GTK_WINDOW (l_engine->window), l_engine->width, l_engine->height);
        g_signal_connect (l_engine->window, "close-request", G_CALLBACK (sbg_on_close_request), l_data);
    } else {
        l_engine->parent = l_box ? l_box : l_parent;
        if (l_box) {
            gtk_box_append (GTK_BOX (l_box), GTK_WIDGET (l_engine->view));
        } else {
            gtk_window_set_child (GTK_WINDOW (l_parent), GTK_WIDGET (l_engine->view));
        }
        l_root = gtk_widget_get_root (l_parent);
        l_engine->window = (l_root && GTK_IS_WINDOW (l_root)) ? GTK_WIDGET (l_root) : l_parent;
    }
    sbg_log ("create engine=%d ephemeral=%d debug=%d embedded=%d", l_id, a_ephemeral, a_debug, l_parent != NULL);
    return l_id;
}

static void *sbg_window (int a_id) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    return l_engine ? (void *) l_engine->window : NULL;
}

/* Release engine `a_id': held decisions are ignored, evaluations still running are cancelled,
   the view leaves its parent and the own window is destroyed. */
static void sbg_dispose (int a_id) {
    sbg_engine_t *l_engine = sbg_engine (a_id);
    gpointer l_data = GINT_TO_POINTER (a_id);
    GtkWidget *l_parent;
    int i;
    if (!l_engine) { return; }
    l_engine->disposing = 1;
    sbg_ignore_held (a_id);
    g_cancellable_cancel (l_engine->cancellable);
    if (l_engine->view) {
        g_signal_handlers_disconnect_by_data (l_engine->view, l_data);
        webkit_web_view_stop_loading (l_engine->view);
    }
    if (l_engine->content_manager) {
        g_signal_handlers_disconnect_by_data (l_engine->content_manager, l_data);
        webkit_user_content_manager_unregister_script_message_handler (l_engine->content_manager, "sb", NULL);
        webkit_user_content_manager_unregister_script_message_handler (l_engine->content_manager, "sb_gtk_frame", NULL);
    }
    if (l_engine->owns_window) {
        if (l_engine->window) {
            g_signal_handlers_disconnect_by_data (l_engine->window, l_data);
            gtk_window_destroy (GTK_WINDOW (l_engine->window));
        }
    } else if (l_engine->view) {
        l_parent = gtk_widget_get_parent (GTK_WIDGET (l_engine->view));
        if (l_parent && GTK_IS_BOX (l_parent)) {
            gtk_box_remove (GTK_BOX (l_parent), GTK_WIDGET (l_engine->view));
        } else if (l_parent && GTK_IS_WINDOW (l_parent)) {
            gtk_window_set_child (GTK_WINDOW (l_parent), NULL);
        }
    }
    if (l_engine->view) { g_object_unref (l_engine->view); }
    if (l_engine->content_manager) { g_object_unref (l_engine->content_manager); }
    if (l_engine->session) { g_object_unref (l_engine->session); }
    if (l_engine->cancellable) { g_object_unref (l_engine->cancellable); }
    for (i = 0; i < SBG_MAX_SCRIPTS; i++) {
        g_free (l_engine->scripts[i].name);
        g_free (l_engine->scripts[i].source);
    }
    for (i = 0; i < SBG_MAX_HINTS; i++) { g_free (l_engine->hints[i].uri); }
    g_free (l_engine->pass_url);
    g_free (l_engine->echo_url);
    sbg_drop_events (a_id);
    sbg_free_event (l_engine->current);
    {
        unsigned int l_serial = l_engine->serial;
        memset (l_engine, 0, sizeof (sbg_engine_t));
        l_engine->serial = l_serial;
    }
    sbg_log ("dispose engine=%d", a_id);
}

#endif /* SB_GTK_H */
