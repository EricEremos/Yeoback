import csv
import html
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEARNING = ROOT / "learning"
FILE_URL = "https://www.figma.com/design/olCrS1PxKWJjMiVlGbC3zR"


def read_json(path):
    return json.loads(path.read_text())


def esc(value):
    return html.escape(str(value), quote=True)


def build():
    originals = read_json(ROOT / "directions.json")
    studies = read_json(ROOT / "style-studies.json")["studies"]
    nodes = {r["key"]: r["id"] for r in read_json(ROOT / "figma-expansion-state.json")["screens"]}
    canonical = {r["key"]: r for r in originals}
    canonical.update({r["id"]: r for r in studies})
    critiques = list(csv.DictReader((LEARNING / "critiques.tsv").open(), delimiter="\t"))
    rules = read_json(LEARNING / "rules.json")
    rule_ids = {r["id"] for r in rules}
    assert len(critiques) == len(canonical) == 150
    assert len({r["id"] for r in critiques}) == 150
    assert {r["id"] for r in critiques} == set(canonical)
    records = []
    for critique in critiques:
        assert None not in critique and all(critique.values())
        key = critique["id"]
        source = canonical[key]
        row = dict(critique)
        row["rules"] = row["rules"].split(",")
        assert set(row["rules"]) <= rule_ids
        assert row["comparison"] in canonical
        original = "key" in source
        row.update({
            "title": source["title"] if original else source["name"],
            "group": "Original concepts" if original else source["group"],
            "intent": source.get("thesis", source.get("principle", "")),
            "original_boundary": source.get("risk", source.get("boundary", "")),
            "source": {"label": source["source"], "url": source["url"], "evidence": "Reference provenance retained from original catalogue; not independently re-audited in this review"} if original else source["source"],
            "figma": FILE_URL + "?node-id=" + (source["node"] if original else nodes[key]).replace(":", "-"),
            "review_scope": "Comparison-scale static artifact inspection; author inference, not user validation",
            "test_status": "Proposed; not executed with participants",
        })
        preview = f"{key}.png" if original else f"{key}-figma.png"
        if not (ROOT / "previews" / preview).exists():
            preview = f"{key[0]}-figma.png"
            row["preview_scope"] = "Group comparison sheet"
        else:
            row["preview_scope"] = "Individual study"
        assert (ROOT / "previews" / preview).exists(), preview
        row["preview"] = "previews/" + preview
        records.append(row)
    counts = dict(Counter(r["disposition"] for r in records))
    result = {"date": "2026-09-05", "status": "150 static reviews complete; design hypotheses and participant tests remain provisional", "counts": counts, "rules": rules, "records": records}
    (LEARNING / "design-analysis.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    cards = []
    for r in records:
        links = " ".join(f'<a href="#rule-{rid}">{rid}</a>' for rid in r["rules"])
        searchable = " ".join([r["id"], r["title"], r["group"], r["observation"], r["lesson"], *r["rules"]]).lower()
        cards.append(f'''<article id="study-{esc(r['id'])}" class="study" data-search="{esc(searchable)}" data-group="{esc(r['group'])}" data-disposition="{esc(r['disposition'])}" data-rules="{esc(' '.join(r['rules']))}">
<div class="eyebrow">{esc(r['group'])} · {esc(r['id'])}</div><h3>{esc(r['title'])}</h3><p class="tag">{esc(r['disposition'])}</p>
<dl><dt>Observed</dt><dd>{esc(r['observation'])}</dd><dt>Transferable lesson</dt><dd>{esc(r['lesson'])}</dd><dt>Next test · proposed</dt><dd>{esc(r['verification_prompt'])}</dd></dl>
<p class="related">Rules {links} · <a class="compare" href="#study-{esc(r['comparison'])}">Compare {esc(r['comparison'])}</a></p>
<details><summary>Original intent and evidence boundary</summary><p>{esc(r['intent'])}</p><p>{esc(r['original_boundary'])}</p><p>{esc(r['review_scope'])}. Tests are proposed, not participant results.</p><p>Reference: <a href="{esc(r['source']['url'])}">{esc(r['source']['label'])}</a><br>{esc(r['source'].get('evidence','Catalogue provenance; source does not validate this study.'))}</p></details>
<div class="cardlinks"><a href="{esc(r['figma'])}">Editable Figma study ↗</a><a href="{esc(r['preview'])}">{esc(r['preview_scope'])} ↗</a></div></article>''')
    rule_cards = []
    for r in rules:
        evidence = ", ".join(f'<a href="#study-{key}" class="compare">{key}</a>' for key in r["evidence"])
        rule_cards.append(f'''<article class="rule" id="rule-{r['id']}"><div class="eyebrow">{r['id']} · {esc(r['status'])}</div><h3>{esc(r['title'])}</h3><p>{esc(r['rule'])}</p><details><summary>Failure, correction and check</summary><p><strong>When:</strong> {esc(r['when'])}</p><p><strong>Counterexample:</strong> {esc(r['counterexample'])}</p><p><strong>Correction:</strong> {esc(r['correction'])}</p><p><strong>Check:</strong> {esc(r['check'])}</p></details><p class="related">Evidence: {evidence}</p></article>''')
    groups = sorted({r["group"] for r in records})
    group_options = ''.join(f'<option>{esc(g)}</option>' for g in groups)
    dispositions = ''.join(f'<option>{esc(d)}</option>' for d in counts)
    rule_options = ''.join(f'<option value="{r["id"]}">{r["id"]} · {esc(r["title"])}</option>' for r in rules)
    page = '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Cleanup · Design Learning Foundation</title><style>
:root{color-scheme:light;--paper:#f4f3ef;--ink:#242b28;--line:#ccd2cb;--muted:#505c55;--accent:#235940}*{box-sizing:border-box}html{scroll-behavior:auto;scroll-padding-top:24px}body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}a{color:var(--accent);text-underline-offset:3px}a:hover{text-decoration-thickness:2px}a:focus-visible,button:focus-visible,input:focus-visible,select:focus-visible,summary:focus-visible{outline:3px solid #7754b2;outline-offset:4px}.skip{position:absolute;left:12px;top:-80px;background:white;padding:10px}.skip:focus{top:10px}header,main,footer{max-width:1440px;margin:auto;padding:32px 40px}header{padding-top:48px}nav{display:flex;gap:24px;flex-wrap:wrap;font-size:14px}.eyebrow{font-size:12px;text-transform:uppercase;letter-spacing:.08em;font-weight:650;color:var(--muted)}h1{font-size:clamp(36px,5vw,66px);line-height:1.04;letter-spacing:-.045em;max-width:850px;margin:24px 0}h2{font-size:30px;letter-spacing:-.025em;line-height:1.2}h3{font-size:21px;line-height:1.2;letter-spacing:-.015em;margin:10px 0 14px}p{margin:12px 0}.intro{max-width:780px;font-size:18px}.stats{display:grid;grid-template-columns:repeat(4,1fr);border-top:1px solid var(--line);border-bottom:1px solid var(--line);margin:32px 0 20px}.stat{padding:20px 12px}.stat strong{display:block;font-size:34px;letter-spacing:-.03em}.note{max-width:1000px;color:var(--muted);font-size:14px}.filters{display:grid;grid-template-columns:2fr 1.2fr 1fr 1.3fr auto;gap:12px;align-items:end;padding:20px;background:#e8ece5;border:1px solid var(--line);border-radius:12px}label{font-size:12px;font-weight:650;display:block}input,select,button{font:inherit;color:inherit;min-height:44px;border:1px solid #78847b;border-radius:6px;background:white;padding:8px 10px;width:100%;margin-top:6px;min-width:0}button{cursor:pointer;background:#235940;color:white;font-weight:600}.resultline{display:flex;justify-content:space-between;gap:20px;flex-wrap:wrap;margin:20px 0;color:var(--muted);font-size:14px}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:20px}.study,.rule{background:#fff;border:1px solid var(--line);border-radius:12px;padding:24px;overflow-wrap:anywhere}.study:target,.rule:target{outline:3px solid #7754b2;outline-offset:3px}.tag{display:inline-block;margin:0 0 12px;padding:3px 10px;background:#edf0ea;border-radius:5px;font-size:12px;font-weight:650}dt{font-size:12px;text-transform:uppercase;letter-spacing:.04em;font-weight:650;color:var(--muted);margin-top:17px}dd{margin:4px 0 0;font-size:15px}.related{font-size:13px;color:var(--muted)}details{border-top:1px solid var(--line);padding-top:12px;margin-top:16px;font-size:14px}summary{cursor:pointer;font-weight:600}.cardlinks{display:flex;flex-wrap:wrap;gap:12px;margin-top:20px;font-size:13px}.rulegrid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}.sectionhead{margin:60px 0 24px;max-width:900px}[hidden]{display:none!important}.empty{padding:40px;background:white;border:1px dashed var(--line)}footer{font-size:13px;color:var(--muted);padding-bottom:60px}code{font-size:.9em}@media(max-width:1000px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.filters{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:600px){header,main,footer{padding-left:20px;padding-right:20px}header{padding-top:28px}.grid,.rulegrid{grid-template-columns:1fr}.stats{grid-template-columns:repeat(2,minmax(0,1fr))}.filters{grid-template-columns:1fr}.study,.rule{padding:20px}nav{gap:12px 20px}}
</style></head><body><a class="skip" href="#catalogue">Skip to individual analyses</a><header><nav><a href="style-lab.html">150 exploration gallery</a><a href="#principles">11 foundation rules</a><a href="DESIGN-FOUNDATION.md">Full synthesis</a><a href="learning/transfer-evidence.md">Transfer & limits</a></nav><p class="eyebrow" style="margin-top:40px">Cleanup / comparative learning / 05 September 2026</p><h1>Learn the decision.<br>Keep the character.</h1><p class="intro">150 individual critiques turn our visual explorations into reusable design knowledge. Every record identifies what is visible, what can transfer, and what still needs testing.</p><div class="stats">__STATS__</div><p class="note">These are working dispositions, not quality scores or a chosen style. A <strong>shell candidate</strong> merits a whole-interface prototype; a <strong>module</strong> serves a bounded task; an <strong>accent</strong> contributes identity; <strong>rework</strong> flags an ambiguity or a rationale mismatch. No participant study or native Cleanup behavior is validated here.</p></header><main><section id="catalogue" aria-labelledby="catalogue-title"><h2 id="catalogue-title">Individual learning ledger</h2><div class="filters"><label for="search">Search ID, name or lesson<input id="search" type="search" placeholder="Try X15, glass, uncertainty…"></label><label for="group">Collection<select id="group"><option value="">All collections</option>__GROUPS__</select></label><label for="disposition">Use in a future design<select id="disposition"><option value="">All dispositions</option>__DISPOSITIONS__</select></label><label for="rule">Foundation rule<select id="rule"><option value="">All rules</option>__RULES__</select></label><button id="reset" type="button">Reset</button></div><div class="resultline"><span id="count" role="status" aria-live="polite">150 of 150 studies</span><span>Static artifact review · source provenance retained</span></div><div id="empty" class="empty" hidden>No studies match. Clear a filter or reset the search.</div><div class="grid">__CARDS__</div></section><section id="principles" aria-labelledby="principles-title"><div class="sectionhead"><p class="eyebrow">Reusable foundation</p><h2 id="principles-title">Eleven rules, with failure cases</h2><p>Project constraints guide future work. Visual hypotheses remain candidates for testing. Each rule links back to concrete studies so the foundation can be checked and revised.</p></div><div class="rulegrid">__RULECARDS__</div></section></main><footer><p>150 explorations do not mean 150 independent design philosophies. Sixteen glass studies use four recorded static layout families. Material, historical reference, information structure and interaction behavior are separate dimensions.</p><p>Review coverage: all 150 comparison-scale artifacts, with selected full-size checks. Proposed verification prompts are not executed user tests. The foundation is saved project knowledge; it does not change model weights.</p><p><a href="learning/design-analysis.json">Machine-readable analyses</a> · <a href="learning/critiques.tsv">Curated 150-row ledger</a> · <a href="learning/protocol.json">Prospective protocol</a></p></footer><script>
const cards=[...document.querySelectorAll('.study')];
const search=document.querySelector('#search'),group=document.querySelector('#group'),disposition=document.querySelector('#disposition'),rule=document.querySelector('#rule');
function filter(){const q=search.value.trim().toLowerCase();let n=0;for(const card of cards){const ok=(!q||card.dataset.search.includes(q))&&(!group.value||card.dataset.group===group.value)&&(!disposition.value||card.dataset.disposition===disposition.value)&&(!rule.value||card.dataset.rules.split(' ').includes(rule.value));card.hidden=!ok;if(ok)n++;}document.querySelector('#count').textContent=`${n} of ${cards.length} studies`;document.querySelector('#empty').hidden=n>0;}
function reset(){search.value='';group.value='';disposition.value='';rule.value='';filter();}
search.addEventListener('input',filter);for(const control of [group,disposition,rule])control.addEventListener('change',filter);document.querySelector('#reset').addEventListener('click',reset);
for(const link of document.querySelectorAll('.compare'))link.addEventListener('click',()=>{reset();const target=document.querySelector(link.hash);if(target){target.setAttribute('tabindex','-1');target.focus({preventScroll:true});}});
function revealHash(){if(location.hash.startsWith('#study-')){reset();const target=document.getElementById(location.hash.slice(1));if(target){target.scrollIntoView({block:'start'});}}}
window.addEventListener('hashchange',revealHash);revealHash();
</script></body></html>'''
    replacements = {"__STATS__": ''.join(f'<div class="stat"><strong>{count}</strong>{esc(label)}</div>' for label, count in counts.items()), "__GROUPS__": group_options, "__DISPOSITIONS__": dispositions, "__RULES__": rule_options, "__CARDS__": '\n'.join(cards), "__RULECARDS__": '\n'.join(rule_cards)}
    for marker, value in replacements.items():
        page = page.replace(marker, value)
    (ROOT / "learning-lab.html").write_text(page)
    print(json.dumps({"records": len(records), "rules": len(rules), "dispositions": counts, "outputs": ["docs/learning/design-analysis.json", "docs/learning-lab.html"]}))


if __name__ == "__main__":
    build()
