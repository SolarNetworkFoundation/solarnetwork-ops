# SNWS2 authentication — basic security audit

_First review 2026-09-14 (central `092b87319`, common `0f65aaa7`). Re-evaluated through 2026-09-16. This version covers
solarnetwork-central `develop` @ `2b4929d1b` and solarnetwork-common `develop` @ `fde30f95`._

_Central now builds against released common artifacts: `snCommonVersion = 4.52.0` and
`snCommonWebJakartaVersion = 2.5.0` ([C] `solarnet/build.gradle:105`, `:115`). The resolved
`net.solarnetwork.common.web.jakarta-2.5.0.jar` was checked directly and contains both
`AuthenticationScheme.matchingHeaderData(String)` and the `MessageDigest.isEqual` comparison in
`AuthenticationDataV2`, so the fixes below are in the code central compiles and runs against — the earlier
"assuming unreleased common changes" caveat no longer applies._

Path prefixes: **[C]** `solarnetwork-central/solarnet/`, **[DB]** `solarnetwork-central/solarnet-db-setup/postgres/`,
**[M]** `solarnetwork-common/`. `…` elides Java package directories.

## Scope and method

- **Spec**: the SolarNet API authentication scheme V2 wiki page.
- **Server implementation**: `Authorization` parsing and verification (`AuthenticationDataFactory`,
  `AuthenticationScheme`, `AuthenticationDataV2`/`V1`, `Snws2AuthorizationBuilder`, `SecurityHttpServletRequestWrapper`
  in [M]); the central `SecurityTokenAuthenticationFilter`, token lookup, and the solarquery/solaruser security configs;
  the signing-key refresh endpoint; components that read the `Authorization` header (content cache, rate limiter, error
  logging); the SolarFlux VerneMQ webhook variant; the DB-side SNWS2 functions.
- **Not covered**: client libraries, SolarNode, the cookie/JWT `AuthenticationDataTokenAuthenticationFilter` in [M]
  (not used by central), proxy and infrastructure configuration, dynamic testing against running apps.
- **Re-evaluations**: reviewed each round of changes, re-ran the parsing harness while header parsing was still in use,
  and rechecked every open finding and line reference. Findings the maintainers decided to accept are marked
  **Closed** with the stated reason.
- **Evidence levels**: _Reproduced_ = demonstrated with a harness built from the verbatim code; _Confirmed_ =
  unambiguous from code and config; _Likely_ = depends on framework behaviour reasoned about but not run.

## Outcome

**All 14 findings are resolved: 11 fixed in code, 3 closed as accepted risk or by design.** Three deliberately
scoped-out items remain, listed under [Remaining optional items](#remaining-optional-items); none is a live
vulnerability.

## Summary

| #  | Severity        | Finding                                                                                                  | Status |
|----|-----------------|----------------------------------------------------------------------------------------------------------|--------|
| 1  | High            | Content cache keyed on header text instead of the authenticated token: cross-user cache disclosure and poisoning in SolarQuery | **Fixed** `463475b25` |
| 2  | Medium          | Tokens owned by disabled user accounts still authenticate (HTTP API and SolarFlux)                       | **Fixed** `f3c3b0785` |
| 3  | Medium          | Token API-path policies matched against the raw URI; `!` (deny) patterns can be sidestepped with percent-encoding | **Fixed** `1dccbd626` |
| 4  | Medium          | Legacy V1 scheme still accepted; it does not bind the body, host, or repeated parameter values           | **Closed**: accepted risk, V1 stays supported for now |
| 5  | Medium          | SolarFlux webhook defaults: raw token secrets as MQTT passwords; node connections with no credential or IP restriction | **Closed**: accepted, all connections pass through a TLS proxy that validates client certificates |
| 6  | Medium (design) | Signing-key refresh allowed by default, so the 7-day key lifetime is not a real bound                    | **Closed**: by design |
| 7  | Low             | Rate-limit bucket chosen from client-controlled request data                                             | **Fixed** `50c25d1e5`, `dc0b13857` |
| 8  | Low             | Token expiry and API-path policy disclosed before the signature is verified                              | **Fixed** `19f56ae51` |
| 9  | Low             | Signature comparisons are not constant-time                                                              | **Fixed** `1f1515f07`, common `fde30f95` (SQL leftover) |
| 10 | Low             | Request bodies read, hashed, and spooled to disk before the token is looked up                           | **Fixed** `386662e23` (spool-cleanup leftover) |
| 11 | Low             | Signatures written to DEBUG logs                                                                         | **Fixed** `8b389f157`, `33d45f52e` |
| 12 | Low             | `Authorization: SNWS2` with no parameters caused an HTTP 500                                             | **Fixed** common `609fdf6d` |
| 13 | Low (adjacent)  | SolarUser allows credentialed CORS from any origin, including the session-cookie UI                      | **Fixed** `f603497e7`, `1a34d6f6a` |
| 14 | Low             | Error handlers log the raw `Authorization` header when there is no authenticated principal               | **Fixed** `c3cddff6c` |

## Change log

Commits are central unless marked common.

| Commit | Effect on findings |
|--------|--------------------|
| common `1d85048f`: `AuthenticationDataV2` keeps the first value of a repeated header parameter | Blocked the originally reported form of #1 |
| common `a96ece5e`: scheme detection required the scheme name followed by a space | Fixed #12, but opened unauthenticated forms of #1 and #7 |
| common `609fdf6d`: scheme detection uses the pattern `^<scheme>\s+`, exposed as `matchingHeaderData` | Closed those unauthenticated forms; **fixed #12** |
| common `fde30f95`: `MessageDigest.isEqual` in `AuthenticationDataV2` | Completed **#9** on the common side |
| `19f56ae51`: signature and date verified before token expiry and API-path policy | **Fixed #8** |
| `8b389f157`: computed signatures no longer logged by the HTTP filter | **Fixed #11** |
| `33d45f52e`: SolarFlux no longer logs the presented signature | Removed the #11 residual |
| `833cd13ce`: SolarFlux raw-secret regex accepts `.` | Fixed the functional bug noted under #5 |
| `25ab89342`, `e44820ca0`: rate-limit regex tweaks | Superseded by `50c25d1e5` |
| `463475b25`: content cache keys on the authenticated token | **Fixed #1** |
| `50c25d1e5`: rate limiter keys on the authenticated token | Fixed #7 for authenticated requests |
| `c3cddff6c`: principal logging no longer falls back to the raw header | **Fixed #14** |
| `f3c3b0785` (NET-523): token auth requires an enabled owning user | **Fixed #2** |
| `1dccbd626`: API-path policy matched against the decoded path | **Fixed #3** |
| `1f1515f07`: constant-time signature comparison in the central filter | **Fixed #9** (Java side) |
| `dc0b13857`: anonymous rate-limit key uses `getRemoteAddr()` only | **Fixed #7** |
| `386662e23`: multipart body pre-read gated on a supported scheme; duplicate filter registration removed | **Fixed #10**; removed a double-execution bug found alongside it |
| `f603497e7`: SolarUser CORS scoped to `/api/**` without credentials; Spring Session JDBC restored | **Fixed #13** |
| `1a34d6f6a`: same CORS treatment in SolarQuery, SolarDIN, SolarDNP3, oscp-fp, oscp-sim-cp | Extended the #13 fix |
| `2b4929d1b`: `UserAuthToken.authSecret` annotated `@JsonIgnore`/`@SerializeIgnore` | Closed the "secret serialization" design note |
| `5e212cc62`, `ea1747518`, `4b8cc9617`, `94feb9142`, `c0317f488`, `7f03950b7` | Not security-related |

## The scheme itself

The core construction is sound and closely follows AWS SigV4: an HMAC-SHA256 signature over a canonical request made of
the method, path, sorted and strictly encoded parameters, a signed header list, and the SHA-256 of the body, using a
key derived per UTC day from the token secret. The server requires `host`, a date header, every `X-SN-*` header, and
any `Content-Type`/`Content-MD5`/`Digest` header to be signed, and it hashes the same cached body bytes that the
application later reads through `getInputStream()`.

Spec-level gaps:

- **Header syntax is unspecified.** The spec doesn't define how duplicate or unknown `Authorization` parameters, or
  the separator after the scheme name, should be handled. This caused #1 and #7. Both are now resolved in code because
  no security decision re-parses the header outside the authentication factory; since `c3cddff6c` the error-logging
  path (#14) no longer returns the raw header either.
- **No replay protection** beyond the date window (15 minutes either side by default). Captured requests, including
  non-idempotent ones, can be replayed inside that window.
- **Key lifetime is open-ended.** Keys are "valid for 7 days", but the refresh flow lets any key holder mint a new key,
  so a derived key is effectively equivalent to the secret until the token is revoked. This is intended (#6).
- **No key scoping.** Unlike SigV4's credential scope, a derived key is not bound to a service or host, the key date is
  not transmitted (servers try seven dates per attempt), and the server accepts whatever `Host` value was signed.
- **V1 is still supported** (#4, accepted).

## Findings

### 1. High — Cross-user content-cache disclosure and poisoning — Fixed

`JCacheContentCachingService` used to take the token segment of its cache key from the raw `Authorization` header with
a substring regex, which could disagree with the token that authentication actually verified. Across the review rounds
that allowed a correctly self-signed request carrying another user's token ID (as a duplicate `Credential`, an
`XCredential=` parameter, or behind a non-space scheme separator) to read or poison that user's cached SolarQuery
responses.

`463475b25` builds the key from `SecurityUtils.currentTokenId()` and no longer reads the header
([C] `common-web/…/JCacheContentCachingService.java:199-205`, folded into the key digest at `:312`). `ContentCachingFilter` (order 0) runs after
the Spring Security filter chain (order −100) has authenticated the request and while the security context is still
populated, so the key identifies the same caller the controller serves; anonymous requests get no identity segment.
This closes every previously reported variant, and the tests build keys from the authenticated token.

Residual hardening (unchanged, not exploitable today): `currentTokenId()` returns `null` for any authenticated
principal that isn't a token ([C] `common/…/security/SecurityUtils.java:367-373`), which would give such requests the
anonymous key. Every cached route is currently reachable only anonymously or with a token. Returning a `null` key
(skip caching) for non-token principals would keep it that way if routes or authentication methods change.

### 2. Medium — Disabled users' tokens keep working — Fixed

`f3c3b0785` (NET-523) filters on the owning user's `enabled` flag in every path that authenticates a token, in SQL
rather than in Java, so the HTTP API and SolarFlux are both covered by one change:

- `solaruser.user_auth_token_login` — the view behind `JdbcUserDetailsService` — now requires `u.enabled = TRUE`
  ([DB] `postgres-init-users.sql:191-202`).
- `solaruser.user_auth_token_node_ids` joins `user_user` and requires `u.enabled = TRUE` ([DB] `:236-241`).
- `snws2_find_verified_token_details`, used by the SolarFlux webhook, joins `user_user` and requires
  `u.enabled = TRUE` ([DB] `:360-395`, condition at `:390`). The same commit qualified the previously ambiguous
  `user_id`/`token_type`/`jpolicy` column references with the `auth` alias.

Suspending an account with `user_user.enabled = false` now revokes API and MQTT access through existing tokens, so form
login and token authentication agree.

Schema change shipped completely: update `[DB] updates/NET-523-token-auth-user-enabled.sql`, migration
`[DB] migrations/migrate-20260915.sql`, the setup DDL above, and the tag in
`[DB] postgres-init-migration-version.sql` bumped to `20260915`.

Tests: `JdbcUserDetailsServiceTests` (disabled owner rejected) and `AuthTokenStoredProcedureTests` (SNWS2 verification
returns nothing for a disabled owner), plus a `CommonDbTestUtils` helper for creating users with an explicit enabled
flag.

### 3. Medium — API-path policy checked against the raw URI — Fixed

`isValidApiPath` previously matched policy patterns against `request.getRequestURI()`, which is not percent-decoded, so
a deny pattern such as `!/user/export/**` did not match `/solaruser/api/v1/sec/user/%65xport/…` even though Spring MVC
routed it to the export controller.

`1dccbd626` adds `decodedPathWithinApplication(...)` ([C] `common-web/…/SecurityTokenAuthenticationFilter.java:332-344`)
and matches against its result ([C] `:273-281`, called at `:239`). Each path segment is percent-decoded as UTF-8 and
normalized the way request mapping does it, and an encoded path separator — which would make the decoded path
ambiguous — is rejected rather than decoded. 102 lines of tests were added to `SecurityTokenAuthenticationFilterTests`.

Leftover, by decision, not a defect in this fix: `SecurityPolicy` still documents OR semantics across mixed patterns
([M] `net.solarnetwork.common/src/net/solarnetwork/domain/SecurityPolicy.java:39-44`, `:116-121`), so
`["/datum/**", "!/datum/export/**"]` allows every path rather than "datum except export". See
[Remaining optional items](#remaining-optional-items).

### 4. Medium — Legacy V1 scheme still accepted — Closed (accepted risk)

**Decision**: V1 remains supported for now.

For the record: `AuthenticationDataFactory` accepts `SolarNetworkWS` in every app
([M] `…/AuthenticationDataFactory.java:82-88`). V1 signs the method, the `Content-MD5` header value, `Content-Type`,
the date, the path, and the sorted parameters using only the first value of each and no encoding
([M] `…/AuthenticationDataV1.java:71-100`). The body check prefers an unsigned `Digest` header over the signed
`Content-MD5` ([M] `…/AuthenticationData.java:100-134`). A captured V1 request can therefore be replayed within the
skew window with a different body, extra values for existing parameters, or against a different host. If V1 is
deprecated later, counting its use first will show which clients still depend on it.

### 5. Medium — SolarFlux webhook defaults — Closed (accepted risk)

**Decision**: accepted, because all MQTT connections pass through a TLS-terminating proxy that validates client
certificates.

For the record: `auth.allowDirectTokenAuthentication` defaults to true
([C] `solarflux-vernemq-webhook/…/config/ServiceConfig.java:67-68`), so raw token secrets can be used as MQTT
passwords; a `solarnode` username is authorized purely by an existing node ID in the client ID
(`…/JdbcAuthService.java:238-263`, `:272-277`), with `auth.nodeIpMask` unset by default
(`ServiceConfig.java:61-62`); and signed MQTT passwords are bearer credentials for the 15-minute window
(`JdbcAuthService.java:116`, `:305-310`). The raw-secret regex now accepts `.` (`JdbcAuthService.java:134-135`). This
acceptance holds only while no broker listener is reachable except through that proxy.

Note that #2 narrowed this: SolarFlux token authentication now also requires an enabled owning user.

### 6. Medium (design) — Signing keys can be refreshed indefinitely — Closed (by design)

**Decision**: indefinite refresh is the intended behaviour.

For the record: `GET /api/v1/sec/auth-tokens/refresh/v2?date=…` returns a new signing key for any date up to today,
for any authenticated request, whether it was signed with the secret or with a derived key
([C] `solarquery/…/web/api/AuthTokenController.java:86-103`). Setting `refreshAllowed: false` on a token's policy is
the per-token opt-out (`:89-92`).

### 7. Low — Rate-limit bucket chosen from client-controlled data — Fixed

Two commits closed this. `50c25d1e5` keys the bucket on `SecurityUtils.currentTokenId()` instead of parsing the header,
so a token request is always charged to the token that was verified. `dc0b13857` then removed the
`X-Forwarded-For` fallback for anonymous requests ([C] `common-web/…/RateLimitingFilter.java:118-121`):

```java
private String requestKey(HttpServletRequest request) {
    String key = SecurityUtils.currentTokenId();
    if ( key == null ) {
        key = request.getRemoteAddr();
    }
    return (keyPrefix != null ? keyPrefix + key : key);
}
```

The public `X_FORWARDED_FOR_HEADER` constant was removed and the class Javadoc now states that the filter does not read
forwarded headers directly ([C] `:51`). An anonymous client can no longer vary a header to dodge its own limit, or
spend another client's bucket by claiming their address.

This relies on `getRemoteAddr()` being the real client address, which was confirmed rather than assumed: SolarQuery and
SolarUser run with `server.forward-headers-strategy: NATIVE`, so Tomcat's `RemoteIpValve` rewrites `getRemoteAddr()`
from the rightmost untrusted `X-Forwarded-For` entry. AWS ALBs append the real peer address to any client-supplied
header (`routing.http.xff_header_processing.mode` defaults to `append`), and the VPC subnet `10.0.0.0/8` is in Spring
Boot's default `server.tomcat.remoteip.internal-proxies` list, so the ALB hop is stripped and the client address
survives. A production auth user event was checked and carried the client IP, not the load balancer's. No extra
`internal-proxies` configuration is needed.

Tests: `RateLimitingFilterTests` gained cases for an anonymous request with a spoofed `X-Forwarded-For` being keyed by
remote address, an over-limit anonymous client varying the header, and one client's header not consuming another's
bucket. Bucket rows outlive the test transaction, so these use randomly generated addresses per test — a first
attempt with fixed addresses deadlocked against Bucket4j's separate connection.

### 8. Low — Token state disclosed before signature verification — Fixed

`19f56ae51` moved the expiry and API-path checks after signature and date verification
([C] `common-web/…/SecurityTokenAuthenticationFilter.java:216-243`) and added tests for both cases. Unknown tokens and
bad signatures now both return `Bad credentials`. Residual (informational): response timing can still differ slightly
between unknown token IDs, where no signature is computed, and known ones.

### 9. Low — Non-constant-time signature comparison — Fixed (SQL leftover)

Both Java comparisons now use `MessageDigest.isEqual`:

- [C] `common-web/…/SecurityTokenAuthenticationFilter.java:219-220` (`1f1515f07`), with the comment "compare in
  constant time to avoid leaking timing information".
- [M] `…/AuthenticationDataV2.java:206` (common `fde30f95`), shipped in the released
  `net.solarnetwork.common.web.jakarta` 2.5.0 that central builds against — verified by disassembling the resolved jar.

Leftover: the SolarFlux SQL path still compares with `=` ([DB] `postgres-init-users.sql:395`). See
[Remaining optional items](#remaining-optional-items).

### 10. Low — Body read and spooled before the token is known — Fixed (spool-cleanup leftover)

The filter used to read the entire multipart body — computing MD5, SHA-1, SHA-256, and SHA-512 — before it looked at
the `Authorization` header at all, so an unauthenticated client could drive sustained CPU and disk load.

**Design discussion.** The pre-read is deliberate and mostly correct: the body must be hashed to verify the signature
anyway, and computing the digests in one pass beats re-reading the content later. The original comment ("for multipart
requests, force the InputStream to be resolved now") was protecting against the servlet container consuming the stream
during parameter parsing. The fix therefore keeps the pre-read but gates it, rather than removing it.

`386662e23` gates the pre-read on the request actually carrying a supported authentication scheme
([C] `common-web/…/SecurityTokenAuthenticationFilter.java:172-177`):

```java
if ( req.getContentType() != null
        && MediaType.MULTIPART_FORM_DATA
                .isCompatibleWith(MimeType.valueOf(req.getContentType()))
        && isSupportedAuthorizationScheme(req.getHeader(HttpHeaders.AUTHORIZATION)) ) {
    request.getContentSHA256();
}
```

`isSupportedAuthorizationScheme` ([C] `:261-269`) tests the header against every `AuthenticationScheme` using
`matchingHeaderData`, so it applies exactly the same scheme-detection rule as the authentication factory. Anonymous and
wrong-scheme multipart requests are no longer read, hashed, or spooled by the filter.

**Found alongside**: `SecurityTokenAuthenticationFilter` was registered twice in four apps — once in the Spring
Security chain, and again by Spring Boot's `ServletContextInitializerBeans`, which auto-registers every `Filter` bean
at `/*`. Confirmed by test (`tokenAuthenticationFilter urls=[/*] order=2147483647`) and by a TRACE startup log. Each
app's `WebSecurityConfig` now adds a disabled `FilterRegistrationBean` ([C] solaruser, solarquery, solarjobs, oscp-fp),
with a generic `WebSecurityConfigTests` regression test in solarquery, solaruser, and oscp-fp asserting that no
security-chain filter bean has an enabled servlet-container registration.

Tests: `SecurityTokenAuthenticationFilterTests` gained cases for multipart with no header, an invalid scheme, and a
valid V2 request, using a `ContentTrackingRequest` that records `getInputStream()`/`getParameterMap()` ordering; an
existing oversized-multipart test was also fixed to actually set the auth header.

Leftover: spool files are still deleted only on failure paths — `fail`, `deny`, and `failDao` each call
`request.deleteCachedContent()` ([C] `:367-390`), while the success path ([C] `:250`) leaves the file to the cleaner
job. See [Remaining optional items](#remaining-optional-items).

### 11. Low — Signatures written to DEBUG logs — Fixed

`8b389f157` removed the computed signature from the HTTP filter's failure log; it now logs only the received value
([C] `common-web/…/SecurityTokenAuthenticationFilter.java:221-222`). `33d45f52e` removed the presented MQTT signature
from SolarFlux's authentication log, which was the remaining part of this finding.

### 12. Low — Malformed scheme header causes an HTTP 500 — Fixed

Common `609fdf6d` detects schemes with the pattern `^<scheme>\s+` and slices the header at the end of that match
([M] `…/AuthenticationScheme.java:49`, `:86-89`; `…/AuthenticationDataFactory.java:83`). A bare `Authorization: SNWS2`
proceeds as anonymous, `SNWS2` followed only by whitespace returns 401 (covered by a test), and `SNWS2x …` is not
treated as V2. Because neither the cache nor the rate limiter parses the header any more, the separator mismatch that an
earlier version of this change introduced no longer matters.

### 13. Low (adjacent) — SolarUser credentialed CORS from any origin — Fixed

SolarUser applied `allowCredentials(true)` with `allowedOriginPatterns("*")` to `/**`, which covered the session-cookie
UI chain (`/u/**`) as well as the token APIs.

**A more serious variant was found while fixing it.** The report originally relied on Spring Session's `SameSite=Lax`
cookie to blunt the impact. That did not hold: SolarUser had lost Spring Session JDBC in the Spring Boot 4 upgrade, so
sessions were plain Tomcat `JSESSIONID` cookies with no `SameSite` attribute at all. Confirmed as a regression —
sessions are meant to persist to `solaruser.http_session` and `solaruser.http_session_attributes`. For any build
deployed in that state, credentialed CORS from an arbitrary origin was not limited to same-site attackers.

`f603497e7` fixes both halves:

- CORS is scoped to the API and drops credentials entirely ([C] `solaruser/…/reg/config/WebConfig.java:281-287`),
  which also removes the reason `allowedOriginPatterns` was needed — Spring rejects `allowedOrigins("*")` only when
  credentials are enabled. The browser UI is now same-origin only.

  ```java
  // allow cross-origin access only to the API, without credentials, as it is authenticated
  // by the Authorization header; the cookie-based browser UI is same-origin only
  registry.addMapping("/api/**")
      .allowedOrigins(CorsConfiguration.ALL)
      .maxAge(TimeUnit.HOURS.toSeconds(24))
      .allowedMethods("GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS", "PATCH")
      .allowedHeaders("Authorization", "Content-MD5", "Content-Type", "Digest", "X-SN-Date")
  ```

- Session persistence is restored by depending on `spring-boot-starter-session-jdbc`
  ([C] `solaruser/build.gradle:53`), and the cookie is pinned explicitly with `same-site: "lax"` alongside
  `http-only: true` ([C] `solaruser/src/main/resources/application.yml:456-461`).

`1a34d6f6a` applies the same treatment to the other apps, all of which authenticate with the `Authorization` header
rather than cookies and so need no credentialed CORS: SolarQuery ([C] `solarquery/…/query/config/WebConfig.java:292-293`),
SolarDIN ([C] `solardin/…/din/app/config/WebConfig.java:101-102`), SolarDNP3
([C] `solardnp3/…/dnp3/app/config/WebConfig.java:83-84`), oscp-fp ([C] `oscp-fp/…/oscp/fp/config/WebConfig.java:68-69`),
and oscp-sim-cp ([C] `oscp-sim-cp/…/oscp/sim/cp/config/WebConfig.java:68-69`).

Historical note, for anyone tempted to reinstate `allowedOriginPatterns`: `87e472650` (Nov 2021) moved CORS into Spring
Security with credentials disabled; `86dee3f11` (Feb 2022) added the max age, OPTIONS, and header list; `40047e7ae`
(Feb 2022) moved it back to WebMVC and turned credentials on — which is what forced the switch to
`allowedOriginPatterns`. With credentials off, `allowedOrigins(ALL)` is valid again and returns `*` rather than echoing
the caller's origin.

Tests: `WebConfigTests` in all six apps (MockMvc preflight assertions for SolarUser, SolarQuery and oscp-fp; registry
inspection via a `TestCorsRegistry` for the rest), including a SolarUser case asserting that a browser page such as
`/login` gets no CORS headers. `HttpSessionTests` asserts the session cookie carries `SameSite=Lax` and `HttpOnly`,
that a row lands in `solaruser.http_session` with `max_inactive_interval` matching the configured timeout, and that
attribute rows land in `solaruser.http_session_attributes`.

### 14. Low — Raw `Authorization` header written to logs — Fixed

`c3cddff6c` removed the raw-header fallback from `WebServiceControllerSupport.userPrincipalName()`
([C] `common-web/…/web/support/WebServiceControllerSupport.java:207-227`). The method now returns the request
principal's name, or the `Credential` parameter parsed from the header, and otherwise the
`ANONYMOUS_USER_PRINCIPAL` placeholder. V1 signatures, `Basic` credentials from the `/ops/**` chains, and bearer
tokens from misdirected clients are therefore no longer written to logs by the exception handlers that can run before
any principal exists (`RequestRejectedException` at WARN, `RuntimeException` at ERROR, `IOException` and
`RateLimitExceededException` at WARN, `BasicSecurityException` at INFO).

This also covers oscp-fp, which uses the same helper ([C] `oscp-fp/…/web/GlobalExceptionHandlers.java:130-131`,
`:176-177`); OSCP's `Token` and `Bearer` headers have no `Credential=` parameter, so they now resolve to the
placeholder instead of being logged verbatim.

## Design notes (informational)

- **Secret serialization** — _resolved by `2b4929d1b`_. `UserAuthToken.getAuthSecret()` is now annotated
  `@SerializeIgnore` and `@JsonIgnore` ([C] `user/…/domain/UserAuthToken.java:236-238`), matching the existing
  `User.getPassword()` pattern, so a query change can no longer expose secrets through the listing API by accident.
  Because token creation genuinely must return the secret once, a new `GeneratedUserAuthToken`
  ([C] `user/…/domain/GeneratedUserAuthToken.java`) wraps the token with `@JsonUnwrapped` and adds the secret back as
  its own property. All three generate endpoints return it (the v1 API `generateToken`, and the UI `generateUserToken`
  and `generateDataToken`), so the JSON response shape is unchanged and `auth-tokens.js` still reads
  `json.data.authSecret`. Caveat: XML/CSV renderings of those three endpoints now nest token fields under `token`,
  because `@JsonUnwrapped` is Jackson-only. Tests: `GeneratedUserAuthTokenTests`, and a `listTokens_withoutSecret`
  case in `UserAuthTokenControllerWebTests`.
- **Plaintext secrets at rest**: `auth_secret varchar(32)` ([DB] `postgres-init-users.sql:178`), readable by any DB role
  that can read the table or the login view, including the SolarFlux webhook's role (its HMAC is computed in SQL).
  This is inherent to HMAC schemes; mitigations are role separation and encryption at rest, which would require moving
  SolarFlux verification out of SQL.
- **Replay window**: ±15 minutes by default
  ([C] `common-web/…/security/web/config/SecurityTokenFilterSettings.java:40`), with no nonce. Consider a shorter
  window for mutating methods, or an idempotency key.
- **Host binding**: the server accepts whatever `Host` value was signed unless `-Dsn.web.auth.explicitHost` is set
  ([M] `…/AuthenticationDataFactory.java:51-53`), so signatures are not bound to one deployment. The unsigned
  `X-Forwarded-Port`/`X-Forwarded-Proto` headers only feed the canonical host value
  ([M] `…/AuthenticationDataV2.java:259-273`); they can break a signature but not forge one.

## Remaining optional items

Deliberately scoped out; none is a live vulnerability.

1. **Deny-overrides policy semantics** (from #3). `SecurityPolicy` documents OR semantics across mixed patterns
   ([M] `…/SecurityPolicy.java:116-121`), so `["/datum/**", "!/datum/export/**"]` allows everything rather than
   "datum except export". The percent-encoding escape is fixed; this is a semantics question about what a `!` pattern
   should mean when combined with allow patterns, and changing it would alter behaviour for existing tokens.
2. **SQL signature comparison** (from #9). `snws2_find_verified_token_details` still compares with `=`
   ([DB] `postgres-init-users.sql:395`). Both Java paths are constant-time; this one is a SQL predicate whose timing is
   dominated by the surrounding query, and remote exploitation is correspondingly harder.
3. **Spool files from successful uploads** (from #10). Deleted only on failure paths ([C]
   `SecurityTokenAuthenticationFilter.java:367-390`); successful requests rely on the cleaner job, which removes files
   older than 10 minutes every 2 minutes ([C] `solaruser/src/main/resources/application.yml:166-168`). Deleting in a
   `finally` after the filter chain would bound disk use tightly, at the cost of holding the file until the response
   completes.

Plus the standing design notes above: plaintext secrets at rest, the ±15-minute replay window, and the lack of host
binding.

## What looked good

- Token IDs (20 characters) and secrets (24–31 characters) come from `SecureRandom` with unbiased selection from a
  65-character alphabet (about 120 and at least 144 bits respectively).
- The string to sign binds the parsed request date, and the date skew is enforced before any token policy details are
  revealed.
- The body hash is computed from the same cached bytes the application reads; spool files are created with
  owner-only permissions.
- The default `StrictHttpFirewall` is active and rejects path traversal, `;`, and encoded separators.
- Token listing endpoints do not return secrets — now enforced by annotation rather than by query shape.
- Neither the content cache nor the rate limiter parses the `Authorization` header any more; both key on the
  authenticated token, and no security decision reads the raw header outside the authentication factory.
- Every fix landed with regression tests: duplicate and unknown parameters, scheme prefixes, check ordering,
  rate-limit keys, cache keys, direct secrets containing `.`, decoded API paths, multipart gating, filter
  registration, CORS preflight in six apps, session persistence and cookie attributes, disabled-user token rejection,
  and token-secret serialization.

## Reproduction harness

`ParserDifferential.java` reproduced the header-parsing divergences behind #1 and #7 while the content cache and the
rate limiter still parsed the header. Both now key on the authenticated token, so no finding depends on the harness; it
reflects the code as of central `4b8cc9617` and is kept for the record only.

`XffCheck.java` is the local Tomcat harness used to confirm `RemoteIpValve` behaviour for #7 — specifically that
`getRemoteAddr()` resolves to the client address and that consumed `X-Forwarded-For` entries are stripped, with and
without a pinned `internal-proxies` list.
