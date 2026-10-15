import Foundation

/// HTML-Seite zum Prüfen der Vorschläge im Browser.
///
/// Liegt im Testordner, die Bilder werden relativ eingebunden. Die Urteile
/// bleiben im Browser gespeichert und lassen sich als CSV herunterladen.
/// Nichts davon verlässt den Mac.
enum Bericht {
    static func html(rows: [Pruefzeile]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(rows)
        let json = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "</", with: "<\\/")
        return template.replacingOccurrences(of: "__ZEILEN__", with: json)
    }

    static let template = #"""
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Kirei · Vorschläge prüfen</title>
<style>
  :root { --bg: #fbfaf7; --fg: #1f1f1c; --muted: #6b6a64; --line: #e4e2db; --accent: #2a4d7a; --ok: #2f6b3a; --bad: #9a3b2f; --card: #ffffff; }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #171716; --fg: #ecebe6; --muted: #9b9a93; --line: #2e2e2b; --accent: #81a3d6; --ok: #7cbf87; --bad: #e08a7c; --card: #1f1f1d; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
  header { position: sticky; top: 0; z-index: 1; background: var(--bg); border-bottom: 1px solid var(--line); padding: 14px 20px; display: flex; flex-wrap: wrap; gap: 12px 20px; align-items: center; }
  h1 { font-size: 17px; margin: 0; font-weight: 600; }
  .stand { color: var(--muted); }
  .hilfe { color: var(--muted); font-size: 13px; flex-basis: 100%; }
  button { font: inherit; border: 1px solid var(--line); background: var(--card); color: var(--fg); border-radius: 8px; padding: 6px 12px; cursor: pointer; }
  button.haupt { background: var(--accent); border-color: var(--accent); color: #fff; }
  main { max-width: 980px; margin: 0 auto; padding: 16px 20px 80px; }
  .zeile { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 14px; margin-bottom: 14px; }
  .zeile.aktiv { outline: 2px solid var(--accent); outline-offset: 2px; }
  .zeile.richtig { border-color: var(--ok); }
  .zeile.falsch { border-color: var(--bad); }
  .bilder { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
  figure { margin: 0; }
  figure img { width: 100%; height: 320px; object-fit: contain; background: var(--bg); border-radius: 8px; }
  figcaption { font-size: 12px; color: var(--muted); margin-top: 4px; word-break: break-all; }
  .info { display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: center; margin-top: 10px; }
  .gruende { flex: 1 1 260px; }
  .urteil { display: flex; gap: 8px; }
  .zeile.richtig .ja, .zeile.falsch .nein { color: #fff; }
  .zeile.richtig .ja { background: var(--ok); border-color: var(--ok); }
  .zeile.falsch .nein { background: var(--bad); border-color: var(--bad); }
  @media (max-width: 640px) { figure img { height: 200px; } }
</style>
</head>
<body>
<header>
  <h1>Vorschläge „ähnlich“ prüfen</h1>
  <span class="stand" id="stand"></span>
  <button class="haupt" id="speichern">Urteile speichern</button>
  <span class="hilfe">Ist das rechte Foto wirklich fast gleich wie das linke? R richtig, F falsch, Pfeiltasten wechseln. Der Stand bleibt in diesem Browser gespeichert.</span>
</header>
<main id="liste"></main>
<script>
const zeilen = __ZEILEN__;
const schluessel = "kirei-urteile-" + location.pathname;
let urteile = {};
try { urteile = JSON.parse(localStorage.getItem(schluessel) || "{}"); } catch (e) {}
let aktuell = 0;

function pfad(p) { return p.split("/").map(encodeURIComponent).join("/"); }
function esc(t) { return String(t).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]); }
function merken() { try { localStorage.setItem(schluessel, JSON.stringify(urteile)); } catch (e) {} }

function stand() {
  const werte = Object.values(urteile);
  const falsch = werte.filter(w => w === "falsch").length;
  document.getElementById("stand").textContent = `${werte.length} von ${zeilen.length} geprüft, davon ${falsch} falsch`;
}

function zeichnen() {
  const liste = document.getElementById("liste");
  liste.innerHTML = "";
  zeilen.forEach((z, i) => {
    const el = document.createElement("section");
    el.className = "zeile" + (urteile[i] ? " " + urteile[i] : "") + (i === aktuell ? " aktiv" : "");
    el.id = "z" + i;
    const abstand = z.abstand == null ? "" : `Abstand ${z.abstand.toFixed(3).replace(".", ",")}`;
    el.innerHTML = `
      <div class="bilder">
        <figure><img loading="lazy" src="${esc(pfad(z.behalten))}" alt="Behalten"><figcaption>Behalten · ${esc(z.behalten)}</figcaption></figure>
        <figure><img loading="lazy" src="${esc(pfad(z.vorschlag))}" alt="Vorschlag"><figcaption>Vorschlag · ${esc(z.vorschlag)}</figcaption></figure>
      </div>
      <div class="info">
        <span class="gruende">Gruppe ${z.gruppe} · ${esc(z.gruende)} ${abstand ? "· " + abstand : ""}</span>
        <span class="urteil">
          <button class="ja">Richtig (R)</button>
          <button class="nein">Falsch (F)</button>
        </span>
      </div>`;
    el.querySelector(".ja").onclick = () => setzen(i, "richtig");
    el.querySelector(".nein").onclick = () => setzen(i, "falsch");
    el.onclick = (e) => { if (e.target.tagName !== "BUTTON") { aktuell = i; markieren(); } };
    liste.appendChild(el);
  });
  stand();
}

function markieren() {
  document.querySelectorAll(".zeile").forEach((el, i) => {
    el.classList.toggle("aktiv", i === aktuell);
    el.classList.toggle("richtig", urteile[i] === "richtig");
    el.classList.toggle("falsch", urteile[i] === "falsch");
  });
  const el = document.getElementById("z" + aktuell);
  if (el) el.scrollIntoView({ block: "center", behavior: "smooth" });
  stand();
}

function setzen(i, wert) {
  urteile[i] = wert;
  merken();
  aktuell = Math.min(i + 1, zeilen.length - 1);
  markieren();
}

function csvFeld(t) {
  t = String(t);
  return /[;"\n]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t;
}

document.getElementById("speichern").onclick = () => {
  const kopf = ["gruppe", "behalten", "vorschlag", "abstand", "gruende", "urteil"];
  const text = [kopf.join(";")].concat(zeilen.map((z, i) => [
    z.gruppe, z.behalten, z.vorschlag,
    z.abstand == null ? "" : z.abstand.toFixed(3).replace(".", ","),
    z.gruende, urteile[i] || ""
  ].map(csvFeld).join(";"))).join("\n") + "\n";
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([text], { type: "text/csv;charset=utf-8" }));
  a.download = "kirei-urteile.csv";
  a.click();
};

document.addEventListener("keydown", (e) => {
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  const k = e.key.toLowerCase();
  if (k === "r") setzen(aktuell, "richtig");
  else if (k === "f") setzen(aktuell, "falsch");
  else if (k === "arrowdown" || k === "j") { aktuell = Math.min(aktuell + 1, zeilen.length - 1); markieren(); e.preventDefault(); }
  else if (k === "arrowup" || k === "k") { aktuell = Math.max(aktuell - 1, 0); markieren(); e.preventDefault(); }
});

zeichnen();
</script>
</body>
</html>
"""#
}
