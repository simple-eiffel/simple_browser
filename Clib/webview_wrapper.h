/*
 * webview_wrapper.h - Wrapper header for webview/webview library
 *
 * This header provides stable C declarations for Eiffel's inline C mechanism.
 * Includes the actual webview API headers.
 *
 * Copyright (c) 2025-2026 Larry Rix
 */

#ifndef WEBVIEW_WRAPPER_H
#define WEBVIEW_WRAPPER_H

/* Include the webview API */
#include "api.h"
#include <string.h>
#include <stdlib.h>

/* Eiffel runtime for GC protection */
#include "eif_eiffel.h"

/*
 * Note: The webview API is defined in api.h which includes:
 * - webview_create
 * - webview_destroy
 * - webview_run
 * - webview_terminate
 * - webview_get_window
 * - webview_set_title
 * - webview_set_size
 * - webview_navigate
 * - webview_set_html
 * - webview_init
 * - webview_eval
 * - webview_bind
 * - webview_unbind
 * - webview_return
 *
 * Functions return webview_error_t (int) where 0 = success.
 * See errors.h for error codes.
 */

/*
 * Callback trampoline for Eiffel JS bindings.
 *
 * We store up to 32 named bindings with their associated Eiffel callbacks.
 * The arg parameter to webview_bind contains the binding index.
 *
 * Each binding holds its Eiffel object through a protected handle
 * (eif_protect), so the reference stays valid when the GC moves the object.
 *
 * webview_run is a `blocking' external: while the message loop runs, this
 * thread is outside Eiffel code and the GC collects (and moves objects)
 * without waiting for it - which is what lets other SCOOP processors or
 * threads collect at all. A callback therefore re-enters Eiffel code
 * (EIF_EXIT_C) before touching any Eiffel object and leaves it again
 * (EIF_ENTER_C) before handing control back to the loop.
 */

#define MAX_BINDINGS 32

/* Eiffel callback function type - calls into Eiffel dispatch routine */
typedef void (*eiffel_callback_t)(void* eiffel_object, const char* name, const char* seq, const char* req);

/* Binding entry */
typedef struct {
    char name[64];
    EIF_OBJECT eiffel_object;   /* Protected handle (eif_protect): follows the object when the GC moves it */
    eiffel_callback_t callback; /* Eiffel dispatch function */
    int in_use;
} webview_binding_t;

/* Global binding registry */
static webview_binding_t g_bindings[MAX_BINDINGS];
static int g_bindings_initialized = 0;

/* Initialize bindings */
static void webview_init_bindings(void) {
    if (!g_bindings_initialized) {
        memset(g_bindings, 0, sizeof(g_bindings));
        g_bindings_initialized = 1;
    }
}

/* Register a binding - store adopted handle for GC protection */
static int webview_register_binding(const char* name, void* eiffel_obj, eiffel_callback_t cb) {
    int i;
    FILE* dbg = fopen("webview_debug.log", "a");
    webview_init_bindings();
    for (i = 0; i < MAX_BINDINGS; i++) {
        if (!g_bindings[i].in_use) {
            strncpy(g_bindings[i].name, name, 63);
            g_bindings[i].name[63] = '\0';
            /* Called from Eiffel code (non-blocking external), so the reference is current */
            g_bindings[i].eiffel_object = eif_protect((EIF_REFERENCE) eiffel_obj);
            g_bindings[i].callback = cb;
            g_bindings[i].in_use = 1;
            if (dbg) {
                fprintf(dbg, "REGISTER: index=%d name=%s obj=%p callback=%p\n",
                    i, name, eiffel_obj, (void*)cb);
                fclose(dbg);
            }
            return i;
        }
    }
    if (dbg) { fprintf(dbg, "REGISTER FAILED: no slots for %s\n", name); fclose(dbg); }
    return -1; /* No slots available */
}

/* Unregister a binding */
static void webview_unregister_binding(const char* name) {
    int i;
    for (i = 0; i < MAX_BINDINGS; i++) {
        if (g_bindings[i].in_use && strcmp(g_bindings[i].name, name) == 0) {
            if (g_bindings[i].eiffel_object != NULL) {
                eif_wean(g_bindings[i].eiffel_object);
            }
            g_bindings[i].eiffel_object = NULL;
            g_bindings[i].in_use = 0;
            break;
        }
    }
}

/* C callback trampoline - called by webview, dispatches to Eiffel */
static void webview_callback_trampoline(const char* seq, const char* req, void* arg) {
    int index = (int)(intptr_t)arg;
    FILE* dbg = fopen("webview_debug.log", "a");
    int was_in_eiffel;

    if (dbg) {
        fprintf(dbg, "TRAMPOLINE: index=%d seq=%s req=%.50s\n", index, seq ? seq : "NULL", req ? req : "NULL");
        fflush(dbg);
    }
    if (index >= 0 && index < MAX_BINDINGS && g_bindings[index].in_use) {
        if (dbg) {
            fprintf(dbg, "  obj=%p callback=%p\n",
                (void*)g_bindings[index].eiffel_object, (void*)g_bindings[index].callback);
            fflush(dbg);
        }
        if (g_bindings[index].callback != NULL && g_bindings[index].eiffel_object != NULL) {
            /* Back into Eiffel code: waits for a collection in progress to finish */
            was_in_eiffel = EIF_IS_IN_EIFFEL_CODE;
            if (!was_in_eiffel) {
                EIF_EXIT_C;
            }

            if (dbg) {
                fprintf(dbg, "DISPATCH: name=%s obj=%p\n",
                    g_bindings[index].name, g_bindings[index].eiffel_object);
                fflush(dbg);
            }
            /* Call Eiffel: ABI expects (Current, a_name, a_seq, a_req) */
            g_bindings[index].callback(
                eif_access(g_bindings[index].eiffel_object),
                g_bindings[index].name,
                seq,
                req
            );
            if (dbg) { fprintf(dbg, "DISPATCH DONE\n"); fflush(dbg); }

            /* Out of Eiffel code again, back to the message loop */
            if (!was_in_eiffel) {
                EIF_ENTER_C;
            }
        } else {
            if (dbg) { fprintf(dbg, "SKIP: callback=%p obj=%p\n",
                (void*)g_bindings[index].callback, (void*)g_bindings[index].eiffel_object); fflush(dbg); }
        }
    } else {
        if (dbg) { fprintf(dbg, "INVALID: index=%d in_use=%d\n", index,
            index >= 0 && index < MAX_BINDINGS ? g_bindings[index].in_use : -1); fflush(dbg); }
    }
    if (dbg) fclose(dbg);
}

#endif /* WEBVIEW_WRAPPER_H */
