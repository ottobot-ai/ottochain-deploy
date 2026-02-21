# Setup Java Build Composite Action

Sets up the Java build environment for OttoChain JARs, including checking out both
`ottobot-ai/ottochain` and `Constellation-Labs/tessellation` at the specified versions.

## Usage Example

```yaml
- name: Setup Java build environment
  uses: ./.github/actions/setup-java-build
  with:
    java_version: '21'
    tessellation_version: 'v4.0.0-rc.2'
    apply_tessellation_patch: 'true'
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `java_version` | No | `'21'` | Java version to use |
| `tessellation_version` | Yes | — | Tessellation version/ref to checkout |
| `apply_tessellation_patch` | No | `'true'` | Whether to apply the tessellation compatibility patch |
| `ottochain_ref` | No | `${{ github.sha }}` | OttoChain ref to checkout |

## Outputs

This action has no direct outputs. It prepares the workspace for sbt builds:

| Side Effect | Description |
|-------------|-------------|
| `ottochain/` | Checked-out OttoChain source code |
| `tessellation/` | Checked-out Tessellation source code |
| Java | Java (Temurin) configured in PATH at specified version |
| sbt | sbt build tool configured and ready |

## Steps

1. **Checkout OttoChain** — `actions/checkout@v4` with `repository: ottobot-ai/ottochain`, `path: ottochain`
2. **Checkout Tessellation** — `actions/checkout@v4` with `repository: Constellation-Labs/tessellation`, `ref: tessellation_version`, `path: tessellation`
3. **Setup Java** — `actions/setup-java@v4` with `distribution: temurin`
4. **Setup sbt** — `sbt/setup-sbt@v1`
5. **Apply tessellation patch** *(conditional)* — Patches `GlobalSnapshotStateChannelEventsProcessor.scala` for OttoChain compatibility

## After Setup

Ready to run sbt commands:

```bash
cd ottochain
sbt assembly
```
