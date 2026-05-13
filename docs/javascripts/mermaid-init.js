// Initialise mermaid for the readthedocs theme.
// pymdownx.superfences emits  <pre class="mermaid"><code>…</code></pre>,
// but mermaid expects the diagram source directly inside the .mermaid node.
// We unwrap the <code> shell first, then let mermaid auto-render.
document.addEventListener("DOMContentLoaded", function () {
  if (typeof mermaid === "undefined") return;

  document.querySelectorAll("pre.mermaid > code").forEach(function (code) {
    var pre = code.parentElement;
    pre.textContent = code.textContent;
  });

  mermaid.initialize({
    startOnLoad: true,
    theme: "default",
    flowchart: { htmlLabels: true, curve: "basis" },
    securityLevel: "loose"
  });
});
