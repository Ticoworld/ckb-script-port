# Frozen R4 fixtures

Genesis:

```text
0xc117b5518c0522988f761f61e6edcb2c59ea6c8e2d787e411c3ee8f5b3794f5b
```

Packed Script:

```text
0x350000001000000030000000310000009d9c7b16af412ae5c3d556bcc061b48ff0e3ba563b1e433e398ff49b516b45e30000000000
```

The fixture generator derives the chain and filter data deterministically from
the pinned upstream test helpers. Matching transaction insertion goes through
the upstream transaction-pool/template path so DAO is calculated from the
complete transaction set.

The historical ranges are exactly `1..H`. Post-H begins at `H+1`; the
post-H matching transactions are appended at the scenario-specific heights
documented in the README.
