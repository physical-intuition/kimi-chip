# Vendored nano-kpu reference (normative)

Source: https://github.com/MoonshotAI/nano-kpu
Commit: e1855debc4469dbfa09b18f34dfcdf9ac7b0f949 (2026-07-23)
License: Apache-2.0 (LICENSE in this directory)

Files copied verbatim from `reference/` (no edits): `__init__.py`,
`config.py`, `model.py`, `prng.py`, `gen_weights.py`. `model.py` is the
arbiter of model semantics; `gen_weights.py` + `prng.py` are the official
seeded synthetic-weight generator. Tests check these SHA-256 digests so a
silent local edit is caught:

```
61da8956a79b6adea9f406af5d05d802d97bdb3e038ccdfc0c91be8f9e47f5ea  reference/__init__.py
c5880699f201380e0acf720be06c39c90aa3efbda13ca4ea4f056763fd2e2744  reference/config.py
ffff8f47692f500aed51ec79a16514f5d31c60e2db0190aadf311f9263b0d5f9  reference/gen_weights.py
a002f6bee18c449829e6b803cc8b9251aa9025b5e31674b9a8b7c819021534a5  reference/model.py
1dc4f7950d1393032ae3f1eafc5989b249021de00509c121dcb14cb1d073a661  reference/prng.py
```

Prose docs (docs/architecture.md, TASK_SPEC.md, interface.md,
quantization.md) were read at the same commit and are not vendored.
