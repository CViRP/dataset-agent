import base64
import io
import json
import platform
import re
import zipfile
from html import escape
from importlib.metadata import version

from .config import ServiceError
from .models import BuildReportInput
from .store import dumps

HTML = """<!doctype html><html lang="{{ language }}" dir="{{ direction }}"><head><meta charset="utf-8">
<title>{{ title }}</title><style>
body{font-family:system-ui,sans-serif;max-width:960px;margin:48px auto;padding:0 24px;color:#17212b}
h1,h2{line-height:1.2}p{line-height:1.6}figure{margin:28px 0}img{max-width:100%}
pre{direction:ltr;text-align:left;white-space:pre-wrap;overflow-wrap:anywhere;background:#f3f5f7;padding:16px;font-size:12px}
small{color:#58636e}.warning{border-left:3px solid #bb8420;padding-left:14px}
</style></head><body><h1>{{ title }}</h1><p>{{ question }}</p>
<h2>{{ labels.findings }}</h2>{% for finding in findings %}<p>{{ finding.text }}</p>
<small>{{ labels.evidence }}: {{ finding.result_ids|join(', ') }}</small>{% else %}
<p>{{ labels.summary }}</p>{% endfor %}
<h2>{{ labels.charts }}</h2>{% for chart in charts %}<figure><img src="data:image/png;base64,{{ chart.base64 }}"
alt="{{ chart.alt_text }}"><figcaption>{{ chart.alt_text }}</figcaption></figure>{% endfor %}
<h2>{{ labels.methods }}</h2>{% for result in results %}<h3>{{ result.tool }}</h3>
<small>{{ result.id }}</small><pre>{{ result.data }}</pre><p>{{ result.method }}</p>{% endfor %}
<h2>{{ labels.limitations }}</h2>{% for warning in warnings %}<p class="warning">{{ warning }}</p>{% endfor %}
<h2>{{ labels.reproducibility }}</h2><pre>{{ provenance }}</pre>
</body></html>"""


def bounded_data(data: dict) -> dict:
    result = dict(data)
    if isinstance(result.get("rows"), list) and len(result["rows"]) > 50:
        result["rows"] = result["rows"][:50]
        result["report_preview_note"] = "First 50 rows; complete stored result is in the ZIP."
    return result


def render_pdf(context: dict, chart_bytes: list[bytes]) -> bytes:
    from reportlab.lib import colors
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.lib.utils import ImageReader
    from reportlab.platypus import Image, Paragraph, SimpleDocTemplate, Spacer

    buffer = io.BytesIO()
    document = SimpleDocTemplate(buffer, title=context["title"], author="Dataset Analysis Agent")
    styles = getSampleStyleSheet()
    story = []

    def paragraph(text, style="BodyText"):
        story.append(Paragraph(escape(str(text)).replace("\n", "<br/>"), styles[style]))
        story.append(Spacer(1, 8))

    paragraph(context["title"], "Title")
    paragraph(context["question"])
    paragraph("Findings", "Heading1")
    for finding in context["findings"]:
        paragraph(finding["text"])
        paragraph("Evidence: " + ", ".join(finding["result_ids"]))
    if not context["findings"]:
        paragraph("Computed evidence report; no model interpretation was requested.")
    for chart, content in zip(context["charts"], chart_bytes):
        width, height = ImageReader(io.BytesIO(content)).getSize()
        story.append(Image(io.BytesIO(content), width=450, height=450 * height / width))
        paragraph(chart["alt_text"])
    paragraph("Evidence and methods", "Heading1")
    for result in context["results"]:
        paragraph(result["tool"], "Heading2")
        paragraph(result["id"])
        # Separate short paragraphs allow pagination of large result objects.
        for line in result["data"].splitlines():
            paragraph(line[:2000], "Code")
        paragraph(result["method"])
    paragraph("Limitations", "Heading1")
    for warning in context["warnings"]:
        paragraph(warning)
    paragraph("Reproducibility", "Heading1")
    for line in context["provenance"].splitlines():
        paragraph(line, "Code")
    styles["Code"].textColor = colors.HexColor("#263238")
    document.build(story)
    return buffer.getvalue()


def build_report(a, args: BuildReportInput):
    from jinja2 import Environment

    results = [a.result(result_id) for result_id in dict.fromkeys(args.result_ids)]
    result_ids = {result["id"] for result in results}
    for finding in args.findings:
        if not set(finding.result_ids).issubset(result_ids):
            raise ServiceError(
                "invalid_evidence", "Finding references evidence not included in this report"
            )
    artifacts = [a.artifact(artifact_id) for artifact_id in dict.fromkeys(args.artifact_ids)]
    if any(artifact["mime_type"] != "image/png" for artifact in artifacts):
        raise ServiceError("invalid_artifact", "Only PNG chart artifacts can be embedded")
    for artifact in artifacts:
        if artifact.get("data_result_id") not in result_ids:
            raise ServiceError(
                "missing_chart_evidence", "Include the query result used to generate each chart"
            )
    chart_bytes = [a.store.path(artifact["path"]).read_bytes() for artifact in artifacts]
    warnings = list(dict.fromkeys(warning for result in results for warning in result["warnings"]))
    warnings.extend(args.limitations)
    warnings.append(
        "Findings are interpretations of the cited results; evidence references do not prove causal claims."
    )
    datasets = [a.dataset(dataset_id) for dataset_id in sorted(a.dataset_ids)]
    provenance = {
        "dataset_versions": [
            {
                "id": dataset["id"],
                "sha256": dataset["sha256"],
                "name": dataset["name"],
                "parent_id": dataset.get("parent_id"),
                "transformations": dataset.get("transformations", []),
                "source_sha256": dataset.get("source", {}).get("sha256"),
            }
            for dataset in datasets
        ],
        "results": [{"id": result["id"], **result["provenance"]} for result in results],
        "python": platform.python_version(),
        "dependencies": {
            name: version(name)
            for name in (
                "agent-dataset",
                "pandas",
                "numpy",
                "duckdb",
                "matplotlib",
                "scipy",
                "statsmodels",
            )
        },
    }
    persian = bool(re.search(r"[\u0600-\u06ff]", args.title + args.question))
    context = {
        "language": "fa" if persian else "en",
        "direction": "rtl" if persian else "ltr",
        "labels": {
            "findings": "یافته‌ها" if persian else "Findings",
            "evidence": "شواهد" if persian else "Evidence",
            "summary": "این گزارش شواهد محاسبه‌شده را ارائه می‌کند. تفسیر مدل درخواست نشده است."
            if persian
            else "This report presents computed evidence. No model interpretation was requested.",
            "charts": "نمودارها" if persian else "Charts",
            "methods": "شواهد و روش‌ها" if persian else "Evidence and methods",
            "limitations": "محدودیت‌ها" if persian else "Limitations",
            "reproducibility": "بازتولیدپذیری" if persian else "Reproducibility",
        },
        "title": args.title,
        "question": args.question,
        "findings": [finding.model_dump() for finding in args.findings],
        "charts": [
            {
                "alt_text": artifact.get("alt_text", "Chart"),
                "base64": base64.b64encode(content).decode("ascii"),
            }
            for artifact, content in zip(artifacts, chart_bytes)
        ],
        "results": [
            {
                "id": result["id"],
                "tool": result["provenance"]["tool"],
                "data": json.dumps(bounded_data(result["data"]), ensure_ascii=False, indent=2),
                "method": dumps(result["provenance"]["arguments"]),
            }
            for result in results
        ],
        "warnings": warnings,
        "provenance": json.dumps(provenance, ensure_ascii=False, indent=2),
    }
    html = Environment(autoescape=True).from_string(HTML).render(**context)
    if args.format == "html":
        content, suffix, mime = html.encode("utf-8"), ".html", "text/html"
    elif args.format == "pdf":
        # Base PDF fonts have limited Unicode coverage. HTML preserves all Unicode text.
        if any(ord(char) > 255 for char in dumps(context)):
            warnings.append(
                "PDF base fonts have limited Unicode coverage; use HTML for multilingual text."
            )
        content, suffix, mime = render_pdf(context, chart_bytes), ".pdf", "application/pdf"
    else:
        parts = [f"# {escape(args.title)}", escape(args.question), "## Findings"]
        for finding in args.findings:
            parts += [escape(finding.text), "Evidence: " + ", ".join(finding.result_ids)]
        for artifact, chart in zip(artifacts, context["charts"]):
            # The ZIP includes these relative image files; standalone .md uses API paths.
            parts.append(
                f"![{escape(chart['alt_text']).replace(']', '')}](/artifacts/{artifact['id']})"
            )
        for result in context["results"]:
            parts += [
                f"## {result['tool']}",
                result["id"],
                "<pre>" + escape(result["data"]) + "</pre>",
            ]
        parts += ["## Limitations", *[escape(warning) for warning in warnings]]
        content, suffix, mime = "\n\n".join(parts).encode("utf-8"), ".md", "text/markdown"
    report = a.store.artifact(
        a.tenant, content, suffix, mime, f"report{suffix}", sorted(a.dataset_ids)
    )
    bundle_buffer = io.BytesIO()
    with zipfile.ZipFile(bundle_buffer, "w", zipfile.ZIP_DEFLATED) as bundle:
        bundle.writestr("report.html", html)
        if suffix != ".html":
            bundle_content = content
            if suffix == ".md":
                markdown = content.decode("utf-8")
                for artifact in artifacts:
                    markdown = markdown.replace(
                        f"/artifacts/{artifact['id']}", f"charts/{artifact['id']}.png"
                    )
                bundle_content = markdown.encode("utf-8")
            bundle.writestr(f"report{suffix}", bundle_content)
        bundle.writestr("manifest.json", context["provenance"])
        bundle.writestr(
            "README.txt",
            "Source datasets are not duplicated in this bundle. Match the immutable dataset IDs and SHA256 checksums in manifest.json. Tool arguments and results record the exact computation; query exports may be capped as disclosed.\n",
        )
        for result in results:
            bundle.writestr(f"results/{result['id']}.json", dumps(result))
            for export in result["artifacts"]:
                stored = a.artifact(export["id"])
                if stored["mime_type"] == "text/csv":
                    bundle.writestr(
                        f"exports/{stored['id']}.csv", a.store.path(stored["path"]).read_bytes()
                    )
        for artifact, raw in zip(artifacts, chart_bytes):
            bundle.writestr(f"charts/{artifact['id']}.png", raw)
    bundle = a.store.artifact(
        a.tenant,
        bundle_buffer.getvalue(),
        ".zip",
        "application/zip",
        "analysis-bundle.zip",
        sorted(a.dataset_ids),
    )
    a.warnings.extend(warnings)
    return {
        "report_id": report["id"],
        "bundle_id": bundle["id"],
        "format": args.format,
        "evidence_count": len(results),
    }, [report, bundle]
