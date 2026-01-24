# 7S-05: SECURITY

**Library**: simple_browser
**Date**: 2026-01-23
**Status**: BACKWASH (reverse-engineered from implementation)

## Security Considerations

### Browser Engine Security

1. **WebView2 Security Model**
   - Chromium security features
   - Process isolation
   - Sandbox for renderer
   - Regular security updates via Edge

2. **Content Security**
   - Default same-origin policy
   - CSP headers respected
   - JavaScript execution controlled

### Eiffel Binding Security

1. **Exposed Functions**
   - Only explicitly bound functions callable from JS
   - Binding name must be known to call
   - Not automatically exposed

2. **Argument Validation**
   - JSON arguments from JavaScript
   - Application must validate input
   - No automatic sanitization

3. **Return Values**
   - Explicit return via return_value/respond
   - Sequence ID prevents confusion
   - Error path via respond_error

### Content Injection

1. **set_html Security**
   - Application controls content
   - User input must be escaped
   - XSS risk if including untrusted data

2. **load_htmx_page**
   - Injects CDN scripts (trusted sources)
   - Body content from application
   - Same escaping requirements

### Navigation Security

1. **URL Navigation**
   - No URL validation in library
   - Application should validate URLs
   - file:// URLs have local access

2. **External Links**
   - Clicks follow in same window
   - No popup blocking by default

### Recommendations

1. **Validate all user input** before including in HTML
2. **Sanitize JavaScript** executed via eval
3. **Validate callback arguments** from JavaScript
4. **Use HTTPS** for external resources
5. **Consider CSP headers** for sensitive apps
6. **Limit exposed bindings** to necessary functions
