/*
 * EventToken.h - the one type WebView2.h takes from the Windows SDK's winrt folder.
 *
 * WebView2.h includes "EventToken.h". The Windows SDK keeps it under Include\<version>\winrt,
 * which the Eiffel C compile does not always have on its include path, so this folder
 * carries the definition itself (the same layout as the SDK's, under the SDK's guard).
 */

#ifndef __eventtoken_h__
#define __eventtoken_h__

typedef struct EventRegistrationToken
{
    __int64 value;
} EventRegistrationToken;

#endif /* __eventtoken_h__ */
