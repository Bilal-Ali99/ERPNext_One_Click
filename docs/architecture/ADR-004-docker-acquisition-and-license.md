# ADR-004: Docker Desktop acquisition and license boundary

Status: Accepted for Phase 0
Date: 2026-10-07

## Decision

- Do not bundle, redistribute, silently upgrade, or silently accept terms for
  Docker Desktop in version 1.
- When Docker Desktop is missing, direct the user to the official Docker route
  and require user-visible acceptance of the applicable Docker terms.
- When Docker Desktop is present but outside the tested range, show the version,
  explain the compatibility state, and allow the user to upgrade or cancel.
- Display the small-business eligibility condition in customer-facing terms:
  fewer than 250 employees **and** less than USD 10M annual revenue. Customers
  outside the free tier are responsible for their Docker entitlement.

## Consequences

- Legal approval is still required for the final EULA wording.
- The installer must not depend on an undocumented third-party installer mirror.
- Docker Desktop support/version testing remains a release-catalog responsibility.
