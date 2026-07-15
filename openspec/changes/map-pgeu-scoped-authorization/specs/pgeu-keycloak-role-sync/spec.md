## MODIFIED Requirements

### Requirement: Object-level PGEU permissions remain local

The SSO role sync SHALL leave PGEU object-level assignments local except for the
fixed scoped capabilities and provenance-controlled lifecycle defined by the
`pgeu-scoped-authorization-sync` capability. Unrecognized relations, public or
registration-type permissions, and unrelated local assignments SHALL remain
outside Keycloak ownership.

#### Scenario: Declared scoped capability is reconciled

- **WHEN** a valid canonical Keycloak scoped grant satisfies identity, object, eligibility, provenance, and safety requirements
- **THEN** role sync may manage only the corresponding allowlisted PGEU relation

#### Scenario: Undeclared object permission is reviewed

- **WHEN** a PGEU object-level assignment has no declared scoped capability or valid Keycloak-owned provenance
- **THEN** role sync leaves that assignment unchanged

#### Scenario: Scoped sync is disabled or rolled back

- **WHEN** the scoped capability is not enabled or is disabled during rollback
- **THEN** the accepted global role mapping continues while object-level assignments remain local
