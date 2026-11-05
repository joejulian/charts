# OpenLDAP

`migration.resources` optionally sets Kubernetes requests and limits for the
`import-version-migration` initializer. Empty defaults preserve existing behavior.
When `migration.enabled` is false, no migration container is rendered, even if
its resource budget is configured. Size import memory for the database being
migrated rather than the idle LDAP server.
