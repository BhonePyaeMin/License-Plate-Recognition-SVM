# Builds docs/Filter_Guide_EN_MY.pdf and docs/Filter_Guide_EN.pdf from guide_content.json, the measurement logs and the figures.
# Run:  python build_guide.py          (needs Microsoft Edge for the PDF printing)
import json, csv, re, os, sys, html, subprocess, glob

SRC = os.path.dirname(os.path.abspath(__file__))            # docs/guide_source
DOCS = os.path.dirname(SRC)
LOGS = os.path.join(SRC, 'measurements')                    # copies of the measurement logs (text)
FIG = os.path.join(SRC, 'fig')
C = json.load(open(os.path.join(SRC, 'guide_content.json'), encoding='utf-8'))
EDGE = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

def esc(s): return html.escape(s, quote=False)

def jpg(name):
    """the picture as a JPEG in fig_jpg/ (noisy photos are 10 times smaller than as PNG); returns the relative path"""
    from PIL import Image
    d = os.path.join(SRC, 'fig_jpg')
    os.makedirs(d, exist_ok=True)
    out = os.path.join(d, os.path.splitext(name)[0] + '.jpg')
    src = os.path.join(FIG, name)
    if not os.path.exists(out) or os.path.getmtime(out) < os.path.getmtime(src):
        Image.open(src).convert('RGB').save(out, quality=86, optimize=True)
    return 'fig_jpg/' + os.path.basename(out)

# ------------------------------------------------------------------ measurement logs
def read_logs(pattern, prefix):
    rows = []
    for f in sorted(glob.glob(os.path.join(LOGS, pattern))):
        for line in open(f, encoding='utf-8', errors='ignore'):
            if line.startswith(prefix) and 'exact' in line:
                p = [x.strip() for x in line.split('|')]
                rows.append(p)
    return rows

def parse_num(p):
    m = re.search(r'exact\s+(\d+)/16', p[-4] if p[0] == 'F6' else p[3])
    return m

f6 = {}
for p in read_logs('pf6*.log', 'F6'):
    ex = int(re.search(r'exact\s+(\d+)/16', p[2]).group(1)); rd = int(re.search(r'read\s+(\d+)/16', p[3]).group(1))
    ch = float(re.search(r'chars\s+([\d.]+)', p[4]).group(1))
    f6[p[1]] = (ex, rd, ch)
persp = {}
for p in read_logs('persp*.log', 'PERSP'):
    ex = int(re.search(r'exact\s+(\d+)/16', p[3]).group(1)); rd = int(re.search(r'read\s+(\d+)/16', p[4]).group(1))
    ch = float(re.search(r'chars\s+([\d.]+)', p[5]).group(1))
    persp[(p[1], p[2])] = (ex, rd, ch)

caps = {}
for cf in ('captions.csv', 'captions2.csv'):
    if os.path.exists(os.path.join(FIG, cf)):
        for r in csv.DictReader(open(os.path.join(FIG, cf), encoding='utf-8')):
            if cf == 'captions.csv' and r['group'] == 'small': continue          # replaced by the harder examples of captions2.csv
            caps.setdefault(r['group'], []).append(r)

# ------------------------------------------------------------------ html helpers
def paras(t, langs, cls=''):
    """t: {'en':..., 'my':...}; one paragraph per language"""
    out = []
    for l in langs:
        if l in t and t[l]:
            out.append('<p class="%s %s">%s</p>' % ('my' if l == 'my' else 'en', cls, esc(t[l])))
    return '\n'.join(out)

def bi(t, langs, sep=' / '):
    return sep.join(esc(t[l]) for l in langs if l in t and t[l])

def reading_cell(r):
    rd, tr = r['reading'], r['truth']
    if rd.startswith('no plate'): cls, mark = 'bad', 'no plate'
    elif rd == tr: cls, mark = 'ok', '&#10003; ' + esc(rd)
    else: cls, mark = 'mid', 'reads ' + esc(rd)
    return '<div class="cap"><b>%s</b><br><span class="%s">%s</span></div>' % (esc(r['label']), cls, mark)

def figrow(group, note=None):
    if group not in caps: return ''
    cells = []
    for r in caps[group]:
        cells.append('<div class="cell"><img src="%s">%s</div>' % (jpg(r['file']), reading_cell(r)))
    n = len(cells)
    return '<div class="figrow" style="grid-template-columns: repeat(%d, 1fr)">%s</div>' % (n if n <= 4 else 3, ''.join(cells))

def table(head, rows, cls='', colw=None):
    h = '<tr>%s</tr>' % ''.join('<th>%s</th>' % c for c in head)
    b = ''.join('<tr>%s</tr>' % ''.join('<td>%s</td>' % c for c in r) for r in rows)
    return '<table class="%s">%s%s</table>' % (cls, h, b)

STR = C['strings']
def S(key, langs): return bi(STR[key], langs)

CSS = """
@page { size: A4; margin: 15mm 14mm 16mm 14mm; }
body { font-family: 'Segoe UI', 'Myanmar Text', Arial, sans-serif; font-size: 10.2pt; line-height: 1.42; color: #1b1f24; }
h1 { font-size: 22pt; margin: 0 0 4px 0; color: #0b3d66; }
h2 { font-size: 15pt; color: #0b3d66; border-bottom: 2px solid #0b3d66; padding-bottom: 3px; margin: 22px 0 8px 0; page-break-after: avoid; }
h3 { font-size: 12.2pt; color: #0b3d66; margin: 14px 0 4px 0; page-break-after: avoid; }
p { margin: 4px 0; }
p.my { font-family: 'Myanmar Text', 'Segoe UI', sans-serif; line-height: 1.7; color: #243447; border-left: 3px solid #c9a227; padding-left: 8px; margin-left: 2px; }
.sub { color: #55606b; font-size: 9.4pt; }
.sec { page-break-inside: avoid; }
.situation { page-break-inside: avoid; margin-bottom: 8px; }
.chain { background: #eef5fb; border: 1px solid #b9d3ea; border-radius: 5px; padding: 6px 9px; margin: 6px 0; font-family: Consolas, monospace; font-size: 9.6pt; }
.nochain { background: #fff4e0; border: 1px solid #e8c581; }
table { border-collapse: collapse; width: 100%; margin: 6px 0 10px 0; font-size: 9.2pt; page-break-inside: avoid; }
th, td { border: 1px solid #c8d0d8; padding: 3px 6px; vertical-align: top; text-align: left; }
th { background: #e6eef6; }
td.n, th.n { text-align: center; white-space: nowrap; }
.warnc { color: #a15c00; font-weight: 600; } .good { color: #1a7f37; font-weight: 600; } .badc { color: #b3261e; font-weight: 600; } .mute { color: #6b7782; }
.figrow { display: grid; gap: 8px; margin: 6px 0 8px 0; }
.cell { min-width: 0; }
.cell img { width: 100%; border: 1px solid #b0b8c0; display: block; image-rendering: auto; }
.cap { font-size: 8.6pt; text-align: center; margin-top: 2px; }
.ok { color: #1a7f37; font-weight: 700; } .mid { color: #a15c00; font-weight: 700; } .bad { color: #b3261e; font-weight: 700; }
.box { border: 1px solid #c8d0d8; border-radius: 6px; padding: 6px 10px; background: #f7f9fb; margin: 8px 0; }
.warn { background: #fff4e0; border-color: #e8c581; }
ol li, ul li { margin-bottom: 3px; }
.small { font-size: 8.8pt; }
.pg { page-break-before: always; }
.filter { page-break-inside: avoid; border-top: 1px solid #dde3e9; padding-top: 4px; margin-top: 6px; }
.filter h3 { margin-top: 4px; }
.lab { font-weight: 700; color: #0b3d66; }
img.shot { max-width: 100%; border: 1px solid #b0b8c0; }
"""

def chain_html(chain, langs):
    if not chain:
        return '<div class="chain nochain">%s</div>' % bi(STR['nofilter'], langs)
    parts = []
    for i, c in enumerate(chain):
        ps = ', '.join('%s %g' % (lab, x) for lab, x in zip(c['labels'], c['p']))
        parts.append('%d. %s: %s' % (i + 1, esc(c['name']), esc(ps)))
    return '<div class="chain">%s</div>' % '<br>'.join(parts)

FIGNOTES = {
 'night_lit': 'Photo car_18 darkened like a lit street, orange lamp cast and noise (simulated). Red outline = plate accepted by the program.',
 'night_dark': 'The same photo, very dark (simulated).',
 'small12': 'Photo car_12 shrunk to 40 % (the plate is about 90 pixels wide).',
 'small09': 'Photo car_09 shrunk to 40 % (the plate is about 114 pixels wide).',
 'dots': 'Photo car_18 with 5 % white and black dots. It is read correctly even without a filter: moderate noise rarely breaks the recogniser, so a filter matters only for harder photos.',
 'grain': 'Photo car_18 with Gaussian noise (sigma 0.06). Read correctly even without a filter, see above.',
 'blur': 'Photo car_18 out of focus (Gaussian blur, sigma 2). Read correctly even without a filter.',
 'flat': 'Photo car_18 with the contrast squeezed to 30 %. Read correctly even without a filter.',
 'shade': 'Photo car_18 with the right side 4 times darker. Read correctly even without a filter.'}

def build(langs, outname):
    L = langs
    h = []
    h.append('<!doctype html><html><head><meta charset="utf-8"><title>%s</title><style>%s</style></head><body>' % (esc(C['title']['en']), CSS))
    h.append('<h1>%s</h1>' % bi(C['title'], L, '<br>'))
    h.append('<p class="sub">%s</p>' % bi(C['subtitle'], L, '<br>'))
    h.append('<div class="box">%s</div>' % paras(C['readfirst'], L))
    # ---- how to use
    h.append('<h2>%s</h2>' % S('h_howto', L))
    h.append('<ol>%s</ol>' % ''.join('<li>%s</li>' % ''.join(paras(s, L)).replace('<p class="en ">', '<span>').replace('<p class="my ">', '<span class="my">').replace('</p>', '</span><br>') for s in C['steps']))
    if os.path.exists(os.path.join(FIG, 'gui_panel.png')):
        h.append('<p><img class="shot" style="max-width:62%%" src="%s"></p><p class="sub">%s</p>' % (jpg('gui_panel.png'), S('cap_panel', L)))
    # ---- quick answer
    h.append('<h2>%s</h2>' % S('h_quick', L))
    head = [S('c_situation', L), S('c_filters', L), S('c_effect', L)]
    rows = []
    for s in C['situations']:
        ch = '<br>'.join('%d. %s: %s' % (i + 1, esc(c['name']), esc(', '.join('%s %g' % (lab, x) for lab, x in zip(c['labels'], c['p'])))) for i, c in enumerate(s['chain'])) if s['chain'] else '<span class="badc">%s</span>' % bi(STR['nofilter_short'], L)
        rows.append([bi(s['title'], L, '<br>'), ch, bi(s['effect'], L, '<br>')])
    h.append(table(head, rows))
    h.append('<div class="box warn">%s</div>' % paras(C['honest'], L))
    # ---- situations
    h.append('<h2 class="pg">%s</h2>' % S('h_situations', L))
    for s in C['situations']:
        h.append('<div class="situation"><h3>%s</h3>' % bi(s['title'], L, ' &mdash; '))
        h.append('<p class="lab">%s</p>' % S('l_filters', L))
        h.append(chain_html(s['chain'], L))
        if s['chain']:
            h.append('<p class="small">%s</p>' % S('l_enter', L))
        h.append('<p class="lab">%s</p>' % S('l_why', L))
        h.append(paras(s['why'], L))
        h.append('<p class="lab">%s</p>' % S('l_measured', L))
        h.append(paras(s['evidence'], L, 'small'))
        for g in s.get('figs', []):
            if g in FIGNOTES: h.append('<p class="sub small">%s</p>' % esc(FIGNOTES[g]))
            h.append(figrow(g))
        h.append('</div>')
    # ---- perspective
    h.append('<h2 class="pg">%s</h2>' % S('h_persp', L))
    h.append(paras(C['persp_intro'], L))
    views = [('front', 'frontal (as photographed)', None), ('yaw 30', 'seen from the side, 30 degrees', 'yaw 30'), ('yaw 50', 'seen from the side, 50 degrees', 'yaw 50'),
             ('pitch 30 (from above)', 'seen from above, 30 degrees', 'pitch 30 (from above)')]
    flt = ['none', 'CLAHE 8 tiles, clip 3', 'Resize x1.5 + unsharp']
    head = [S('c_view', L)] + [esc(x) for x in ['no filter', 'CLAHE', 'enlarge x1.5 + unsharp']]
    rows = []
    front_none = f6.get('none')
    FRONT = {'CLAHE 8 tiles, clip 3': (9, 0, 70.7), 'Resize x1.5 + unsharp': (9, 0, 71.5)}      # earlier run on the original photos
    for key, name, pk in views:
        row = [name]
        for fl in flt:
            if pk is None:
                v = front_none if fl == 'none' else FRONT.get(fl)
            else:
                v = persp.get((pk, fl))
            row.append('<span class="mute">&ndash;</span>' if v is None else '<b>%d</b>/16 <span class="mute">(%.1f %%)</span>' % (v[0], v[2]))
        rows.append(row)
    h.append('<p class="lab">%s</p>' % S('l_persptable', L))
    h.append(table(head, rows, 'n'))
    h.append(paras(C['persp_note'], L, 'small'))
    for who, title in (('car_18', 'frontal photo (car_18)'), ('car_30', 'oblique photo (car_30)')):
        h.append('<h3>%s</h3>' % esc(title))
        for vk in ('front', 'yaw30', 'yaw50', 'pitch30'):
            g = 'persp_%s_%s' % (who, vk)
            if g in caps:
                h.append('<p class="sub">%s</p>' % esc({'front': 'as photographed', 'yaw30': 'from the side 30 deg', 'yaw50': 'from the side 50 deg', 'pitch30': 'from above 30 deg'}[vk]))
                h.append(figrow(g))
    h.append(paras(C['persp_advice'], L))
    # ---- many plates at once
    h.append('<h2 class="pg">%s</h2>' % S('h_many', L))
    h.append(paras(C['many_intro'], L))
    if os.path.exists(os.path.join(FIG, 'many_night.png')):
        h.append('<p><img class="shot" src="%s"></p><p class="sub">%s</p>' % (jpg('many_night.png'), S('cap_many', L)))
    h.append(paras(C['many_limits'], L, 'small'))
    h.append(paras(C['engine_new'], L, 'small'))
    h.append(paras(C['small_boost'], L, 'small'))
    h.append(paras(C['vehicles_results'], L, 'small'))
    # ---- own photo
    if 'own_dark' in caps:
        h.append('<h2>%s</h2>' % S('h_own', L))
        h.append(paras(C['own_dark'], L))
        h.append('<div class="figrow" style="grid-template-columns: repeat(3, 1fr)">%s</div>' % ''.join('<div class="cell"><img src="%s">%s</div>' % (jpg(r['file']), reading_cell(r)) for r in caps['own_dark']))
    # ---- 17 filters test
    h.append('<h2>%s</h2>' % S('h_f17', L))
    h.append(paras(C['f17_intro'], L))
    head = [S('c_filter', L), S('c_exact', L), S('c_read', L), S('c_chars', L), S('c_verdict', L)]
    rows = []
    base = f6.get('none')
    for f in C['filters']:
        v = f6.get(f['name'])
        if v is None:
            rows.append([esc(f['name']), '&ndash;', '&ndash;', '&ndash;', '']); continue
        if base:
            if v[0] <= base[0] - 2: verdict = '<span class="badc">%s</span>' % bi(STR['v_worse'], L)
            elif v[0] < base[0] or v[2] <= base[2] - 5: verdict = '<span class="warnc">%s</span>' % bi(STR['v_slight'], L)
            else: verdict = '<span class="mute">%s</span>' % bi(STR['v_same'], L)
        else: verdict = ''
        rows.append([esc(f['name']), '%d / 16' % v[0], '%d / 16' % v[1], '%.1f %%' % v[2], verdict])
    if base:
        rows.insert(0, ['<b>%s</b>' % bi(STR['nofilter_short'], L), '<b>%d / 16</b>' % base[0], '%d / 16' % base[1], '%.1f %%' % base[2], ''])
    h.append(table(head, rows, 'n'))
    h.append(paras(C['f17_note'], L, 'small'))
    # ---- filter reference
    h.append('<h2 class="pg">%s</h2>' % S('h_ref', L))
    for f in C['filters']:
        h.append('<div class="filter"><h3>%s <span class="mute small">&mdash; %s</span></h3>' % (esc(f['name']), bi(f['group'], L)))
        h.append('<p class="lab">%s</p>%s' % (S('l_how', L), paras(f['how'], L)))
        h.append('<p class="lab">%s</p>%s' % (S('l_good', L), paras(f['good'], L)))
        h.append('<p class="lab">%s</p>%s' % (S('l_bad', L), paras(f['bad'], L)))
        h.append('<p class="small"><span class="lab">%s</span> %s</p></div>' % (S('l_params', L), esc(f['params'])))
    # ---- troubleshooting
    h.append('<h2 class="pg">%s</h2>' % S('h_trouble', L))
    for t in C['trouble']:
        h.append('<h3>%s</h3>' % bi(t['q'], L, ' / '))
        h.append(paras(t['a'], L))
    # ---- method
    h.append('<h2>%s</h2>' % S('h_method', L))
    h.append(paras(C['method'], L, 'small'))
    h.append('</body></html>')
    out = os.path.join(SRC, outname + '.html')
    open(out, 'w', encoding='utf-8').write('\n'.join(h))
    pdf = os.path.join(DOCS, outname + '.pdf')
    if os.path.exists(pdf): os.remove(pdf)
    subprocess.run([EDGE, '--headless=new', '--disable-gpu', '--no-pdf-header-footer', '--print-to-pdf=' + pdf, 'file:///' + out.replace('\\', '/')],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=240)
    print(outname, 'pdf' if os.path.exists(pdf) else 'FAILED', os.path.getsize(pdf) if os.path.exists(pdf) else 0)

if __name__ == '__main__':
    which = sys.argv[1] if len(sys.argv) > 1 else 'both'
    if which in ('both', 'en'): build(['en'], 'Filter_Guide_EN')
    if which in ('both', 'my'): build(['en', 'my'], 'Filter_Guide_EN_MY')
