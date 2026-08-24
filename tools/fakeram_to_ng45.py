#!/usr/bin/env python3
"""fakeram_to_ng45.py <asap7_fakeram.lef> <out_prefix>

Convert ASAP7-style fakeram SRAM macros to Nangate45 (FreePDK45), emitting
<out_prefix>.lef and <out_prefix>.lib. Self-contained; no external deps.

LEF: geometry rescaled by sqrt(45nm/7nm bitcell area ratio) and re-emitted in
the conventions of ORFS's shipped fakeram45 macros:
  - SIZE snapped to the 1.4um site row height / 0.19um x-grid
  - signal pins: 0.070um metal3 stubs, left edge (spill right), 0.28 pitch
  - PG: vertical metal4 straps, 0.28 wide, alternating VSS/VDD, 2.24 pitch
  - OBS: metal1/2 full body; metal3 body minus pin slots; metal4 between straps

LIB: written fresh with 45nm-plausible SRAM timing, derived from geometry via
an explicit model (transparent > precise; tune the constants if you have
compiler data):
  clk->Q access:  0.35ns + 0.03ns * log2(bits)      (16Kb leaf -> ~0.77ns)
  input setup:    0.15ns   hold: 0.03ns
  pin cap:        0.005pF  (address/control), 0.004pF (data)
These are deliberately conservative vs published 45nm compiler datasheets, so
timing signoff UNDER-promises: if the chip closes with this lib, real SRAMs
only help.
"""
import math
import re
import sys

SCALE = 3.486          # sqrt(bitcell area ratio), matches fakeram45 sizing
ROW_H = 1.4            # ng45 site row height (um)
XGRID = 0.19           # ng45 x snap (M2 pitch)
PIN_W = 0.070          # metal3 pin stub width (um)
PIN_PITCH = 0.28       # pin pitch (um)
PIN_Y0 = 2.80          # first pin y
PIN_LEN = 0.19         # stub length into the macro
PG_W = 0.28            # metal4 strap width
PG_PITCH = 2.24        # strap pitch
PG_MARGIN = 2.80       # strap y-inset from macro edge


def r3(x):
    return round(x, 3)


def parse_macros(lef_text):
    """Yield (name, width, height, [(pin, dir), ...]) per MACRO."""
    for m in re.finditer(r'^MACRO (\S+)\s*\n(.*?)^END \1\s*$',
                         lef_text, re.M | re.S):
        name, body = m.group(1), m.group(2)
        w, h = map(float, re.search(r'SIZE ([\d.]+) BY ([\d.]+)', body).groups())
        pins = []
        for pm in re.finditer(
                r'PIN (\S+)\s*\n\s*DIRECTION (\w+)\s*;(.*?)END \1', body, re.S):
            pname, pdir, pbody = pm.group(1), pm.group(2), pm.group(3)
            if 'USE POWER' in pbody or 'USE GROUND' in pbody:
                continue
            pins.append((pname, pdir))
        yield name, w, h, pins


def emit_lef(macros, out):
    L = ['VERSION 5.7 ;', 'BUSBITCHARS "[]" ;', 'DIVIDERCHAR "/" ;', '']
    for name, w0, h0, pins in macros:
        w = r3(math.ceil(w0 * SCALE / XGRID) * XGRID)
        h = r3(math.ceil(h0 * SCALE / ROW_H) * ROW_H)
        L += [f'MACRO {name}', '  CLASS BLOCK ;', f'  FOREIGN {name} 0 0 ;',
              '  ORIGIN 0 0 ;', f'  SIZE {w} BY {h} ;', '  SYMMETRY X Y R90 ;']
        # --- signal pins: left edge first, spill to right ---
        per_edge = max(1, int((h - 2 * PIN_Y0) / PIN_PITCH))
        slots = []  # (edge, y) per pin, for OBS carve-outs
        for i, (pname, pdir) in enumerate(pins):
            left = i < per_edge
            k = i if left else i - per_edge
            y = r3(PIN_Y0 + k * PIN_PITCH)
            x0, x1 = (0.0, PIN_LEN) if left else (r3(w - PIN_LEN), w)
            slots.append((y, x0, x1))
            L += [f'  PIN {pname}', f'    DIRECTION {pdir} ;',
                  '    USE SIGNAL ;', '    PORT', '      LAYER metal3 ;',
                  f'      RECT {x0} {r3(y - PIN_W/2)} {x1} {r3(y + PIN_W/2)} ;',
                  '    END', f'  END {pname}']
        # --- PG straps on metal4 ---
        n_straps = max(2, int((w - 2 * PG_MARGIN) / PG_PITCH))
        strap_x = []
        for s in range(n_straps):
            x = r3(PG_MARGIN + s * PG_PITCH)
            strap_x.append(x)
            net, use = (('VSS', 'GROUND') if s % 2 == 0 else ('VDD', 'POWER'))
            L += [f'  PIN {net}', '    DIRECTION INOUT ;', f'    USE {use} ;',
                  '    PORT', '      LAYER metal4 ;',
                  f'      RECT {x} {PG_MARGIN} {r3(x + PG_W)} {r3(h - PG_MARGIN)} ;',
                  '    END', f'  END {net}']
        # --- OBS ---
        L += ['  OBS',
              '    LAYER metal1 ;', f'    RECT 0 0 {w} {h} ;',
              '    LAYER metal2 ;', f'    RECT 0 0 {w} {h} ;',
              '    LAYER metal3 ;']
        # metal3: full body minus a clearance band at each pin row edge
        band = PIN_PITCH / 2
        prev = 0.0
        for y, x0, x1 in sorted(slots) + [(h, 0, 0)]:
            lo, hi = r3(prev), r3(max(prev, y - band))
            if hi > lo:
                L.append(f'    RECT {PIN_LEN} {lo} {r3(w - PIN_LEN)} {hi} ;')
            prev = y + band
        L.append('    LAYER metal4 ;')
        prev = 0.0
        for x in strap_x + [w]:
            lo, hi = r3(prev), r3(max(prev, x - 0.07))
            if hi > lo:
                L.append(f'    RECT {lo} 0 {hi} {h} ;')
            prev = (x + PG_W + 0.07) if x != w else x
        L += ['  END', f'END {name}', '']
    open(out, 'w').write('\n'.join(L))


def emit_lib(macros, out, corner='typical'):
    L = [f'library (fakeram_ng45_{corner}) {{',
         '  delay_model : table_lookup;',
         '  time_unit : "1ns"; voltage_unit : "1V"; current_unit : "1mA";',
         '  capacitive_load_unit (1,pf);',
         '  slew_upper_threshold_pct_rise : 80; slew_lower_threshold_pct_rise : 20;',
         '  slew_upper_threshold_pct_fall : 80; slew_lower_threshold_pct_fall : 20;',
         '  input_threshold_pct_rise : 50; input_threshold_pct_fall : 50;',
         '  output_threshold_pct_rise : 50; output_threshold_pct_fall : 50;',
         '  nom_process : 1; nom_voltage : 1.1; nom_temperature : 25;',
         '  operating_conditions (typ) { process : 1; voltage : 1.1; temperature : 25; }']
    # bus types
    widths = set()
    for _, _, _, pins in macros:
        for pname, _ in pins:
            m = re.match(r'.*\[(\d+)\]$', pname)
            if m:
                widths.add(int(m.group(1)) + 1)
    for name, w0, h0, pins in macros:
        # geometry -> bits estimate for the access model
        bits_m = re.search(r'(\d+)x(\d+)', name)
        bits = (int(bits_m.group(1)) * int(bits_m.group(2))) if bits_m else 16384
        t_acc = round(0.35 + 0.03 * math.log2(max(2, bits)), 3)
        w = r3(w0 * SCALE)
        h = r3(h0 * SCALE)
        L += [f'  cell ({name}) {{',
              f'    area : {r3(w*h)};', '    interface_timing : true;']
        # group bus pins into scalars (fakeram pins are bit-blasted names)
        clks = [p for p, d in pins if p.endswith('_clk')]
        for pname, pdir in pins:
            direction = 'output' if pdir.upper() == 'OUTPUT' else 'input'
            L.append(f'    pin ("{pname}") {{')
            L.append(f'      direction : {direction};')
            if pname in clks:
                L.append('      clock : true;')
            if direction == 'input':
                cap = 0.005 if not re.search(r'data', pname) else 0.004
                L.append(f'      capacitance : {cap};')
                rel = clks[0] if clks else 'clk'
                if pname not in clks:
                    L += [f'      timing () {{ related_pin : "{rel}";',
                          '        timing_type : setup_rising;',
                          '        rise_constraint(scalar){values("0.15");}',
                          '        fall_constraint(scalar){values("0.15");} }',
                          f'      timing () {{ related_pin : "{rel}";',
                          '        timing_type : hold_rising;',
                          '        rise_constraint(scalar){values("0.03");}',
                          '        fall_constraint(scalar){values("0.03");} }']
            else:
                rel = clks[0] if clks else 'clk'
                L += ['      max_capacitance : 0.10;',
                      f'      timing () {{ related_pin : "{rel}";',
                      '        timing_type : rising_edge;',
                      f'        cell_rise(scalar){{values("{t_acc}");}}',
                      f'        cell_fall(scalar){{values("{t_acc}");}}',
                      '        rise_transition(scalar){values("0.10");}',
                      '        fall_transition(scalar){values("0.10");} }']
            L.append('    }')
        L.append('  }')
    L.append('}')
    open(out, 'w').write('\n'.join(L))


def main():
    src, prefix = sys.argv[1], sys.argv[2]
    macros = list(parse_macros(open(src).read()))
    emit_lef(macros, prefix + '.lef')
    emit_lib(macros, prefix + '.lib')
    for name, w0, h0, pins in macros:
        bits_m = re.search(r'(\d+)x(\d+)', name)
        bits = (int(bits_m.group(1)) * int(bits_m.group(2))) if bits_m else 0
        t_acc = round(0.35 + 0.03 * math.log2(max(2, bits)), 3)
        print(f'{name}: {r3(w0*SCALE)}x{r3(h0*SCALE)}um  {len(pins)} pins  '
              f'clk->Q={t_acc}ns')


if __name__ == '__main__':
    main()
