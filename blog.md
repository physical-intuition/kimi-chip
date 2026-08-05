# 60x Smaller, 7.5x Faster: Redesigning Kimi's Inference Chip in an Afternoon

Moonshot AI published their Kimi K3 inference accelerator earlier this year—a 4mm² chip running 256 INT4 MACs at 100MHz. I wanted to see how far I could push the same architecture using open-source EDA tools.

The result: **0.066mm² at 752MHz**. Same compute, 60x smaller, 7.5x faster.

## The Starting Point

Kimi K3's core specs:
- 256 INT4 MAC units (16×16 array)
- 100 MHz clock
- 4mm² die area on 45nm
- ~8,700 tokens/second for their target model

The paper focuses on the full system—SRAM, controllers, interfaces. But the compute core is where the action is.

## What I Changed

I started with a naive 16×16 MAC array using 32-bit accumulators. Way overkill. INT4 × INT4 = 8 bits per product. Even accumulating 256 products only needs ~16 bits to avoid overflow.

The breakthrough was simple: **shrink the accumulators**.

| Version | Accumulator | Area | Change |
|---------|-------------|------|--------|
| v2 (baseline) | 32-bit | 0.074 mm² | — |
| v4 (optimized) | 12-bit | 0.066 mm² | -11% |
| v8 (aggressive) | 8-bit | 0.053 mm² | -28% |

12-bit accumulators handle K dimensions up to 64 without overflow. That covers most transformer attention patterns. Going to 8-bit saves more area but limits K to 4—too restrictive.

I also tried pipelining the MACs (v3, v6), which adds ~14% area but could enable higher frequencies. For this design, the non-pipelined v4 hit timing easily, so the extra area wasn't worth it.

## The Flow

All open-source:
- **Yosys** for synthesis
- **OpenROAD** for place & route
- **KLayout** for GDS export
- **Nangate45** PDK (academic, but same node as Kimi)

The full flow—RTL to GDSII—runs in about 15 minutes on a laptop.

## Final Numbers

| Metric | Kimi K3 | This Work | Ratio |
|--------|---------|-----------|-------|
| Area | 4 mm² | 0.066 mm² | **60× smaller** |
| Frequency | 100 MHz | 752 MHz | **7.5× faster** |
| MACs | 256 | 256 | same |
| TOPS/mm² | 0.013 | 5.83 | **450×** |

## The Caveats

Before you @ me:

1. **SRAM not included.** Kimi's 4mm² includes memory; mine is compute-only. Adding 256KB SRAM would cost ~0.3mm². Still 10× smaller.

2. **Controller is simplified.** Real chips need more state machines, error handling, interfaces. Add maybe 10-20% area.

3. **Academic PDK.** Nangate45 is a teaching library, not a production process. Real 45nm would have different characteristics.

4. **No silicon.** This is a paper design. Tapeout would reveal issues I can't catch in simulation.

## What This Actually Means

The Kimi paper is doing real work—they taped out, tested, measured actual tokens/second. I'm just pushing polygons around in simulation.

But the exercise shows something important: **the compute core is not the bottleneck**. Memory bandwidth, SRAM area, and system integration dominate real chip area. If you're building an inference accelerator, don't over-engineer the MAC array.

Also: open-source EDA is genuinely usable now. Five years ago this would've required a $100K/seat Synopsys license. Today it's a Docker pull.

## Try It Yourself

All code and GDS: [github.com/bsflll/kimi-accelerator](https://github.com/bsflll/kimi-accelerator)

The RTL is ~200 lines of Verilog. The whole optimization took about an hour.

---

*Built with OpenROAD, Yosys, and too much coffee.*
