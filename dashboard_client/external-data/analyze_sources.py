"""Maak een technische samenvatting, indicatorcatalogus en checksums.

Dit script wijzigt de ruwe downloads niet. De uitvoer is bedoeld om de
bestanden later gecontroleerd aan de Dynamo-monitor te kunnen koppelen.
"""

from __future__ import annotations

import csv
import hashlib
import json
import re
import zipfile
from collections import Counter
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"


ODATA = [
    ("RIVM Beweegvriendelijke omgeving", "rivm_beweegvriendelijke_omgeving_50143NED"),
    ("RIVM Gezondheid wijk/buurt", "rivm_gezondheid_wijk_buurt_50150NED"),
    ("RIVM Regiobeeld wijk/buurt", "rivm_regiobeeld_wijk_buurt_50149NED"),
    ("CBS SES-WOA", "cbs_ses_woa_86296NED"),
    ("CBS Nabijheid voorzieningen", "cbs_nabijheid_voorzieningen_86270NED"),
    ("CBS Sociaal domein", "cbs_sociaal_domein_85994NED"),
    ("CBS Wmo naar type", "cbs_wmo_type_86158NED"),
    ("CBS Jeugdzorg wijken", "cbs_jeugdzorg_wijken_86204NED"),
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def group_path(item: dict, by_id: dict[int, dict]) -> str:
    names = []
    parent = item.get("ParentID")
    while parent is not None and parent in by_id:
        node = by_id[parent]
        if node.get("Title"):
            names.append(str(node["Title"]))
        parent = node.get("ParentID")
    return " > ".join(reversed(names))


def inspect_odata(name: str, slug: str) -> tuple[dict, list[dict]]:
    folder = RAW / slug
    data_path = folder / "data.csv"
    properties = json.loads((folder / "metadata" / "DataProperties.json").read_text(encoding="utf-8"))
    table_infos = json.loads((folder / "metadata" / "TableInfos.json").read_text(encoding="utf-8"))
    table = table_infos[0]
    topics = [item for item in properties if item.get("Type") == "Topic"]
    topic_keys = [str(item["Key"]) for item in topics]
    by_id = {int(item["ID"]): item for item in properties if item.get("ID") is not None}

    rows = 0
    years: set[str] = set()
    region_codes: set[str] = set()
    level_counts: Counter[str] = Counter()
    amsterdam_rows = 0
    nonempty_topics: Counter[str] = Counter()
    amsterdam_nonempty_topics: Counter[str] = Counter()
    with data_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fields = reader.fieldnames or []
        code_field = next((f for f in ("Codering_3", "WijkenEnBuurten", "Wijken") if f in fields), None)
        for row in reader:
            rows += 1
            period = (row.get("Perioden") or "").strip()
            if period:
                years.add(period[:4])
            code = (row.get(code_field) or "").strip() if code_field else ""
            if code:
                region_codes.add(code)
                level = "buurt" if code.startswith("BU") else "wijk" if code.startswith("WK") else "gemeente" if code.startswith("GM") else "land" if code.startswith("NL") else "overig"
                level_counts[level] += 1
            is_amsterdam = code.startswith(("GM0363", "WK0363", "BU0363"))
            if is_amsterdam:
                amsterdam_rows += 1
            for key in topic_keys:
                value = row.get(key)
                if value not in (None, "", ".", "NA"):
                    nonempty_topics[key] += 1
                    if is_amsterdam:
                        amsterdam_nonempty_topics[key] += 1

    indicators = []
    for item in topics:
        key = str(item["Key"])
        indicators.append(
            {
                "source": name,
                "dataset_id": table.get("Identifier", ""),
                "table_title": table.get("Title", ""),
                "variable": key,
                "theme": group_path(item, by_id),
                "label": item.get("Title", ""),
                "definition": item.get("Description", ""),
                "unit": item.get("Unit", ""),
                "decimals": item.get("Decimals", ""),
                "period": table.get("Period", ""),
                "source_detail": table.get("Source", ""),
                "geography": "buurt/wijk/gemeente" if "buurt" in table.get("Title", "").lower() else "wijk/gemeente",
                "nonempty_rows": nonempty_topics[key],
                "nonempty_amsterdam_rows": amsterdam_nonempty_topics[key],
            }
        )

    summary = {
        "source": name,
        "slug": slug,
        "table_id": table.get("Identifier"),
        "title": table.get("Title"),
        "modified": table.get("Modified"),
        "period": table.get("Period"),
        "rows": rows,
        "columns": len(fields),
        "topics": len(topics),
        "years_in_download": sorted(years),
        "unique_region_codes": len(region_codes),
        "row_levels": dict(level_counts),
        "amsterdam_rows": amsterdam_rows,
        "file_bytes": data_path.stat().st_size,
    }
    return summary, indicators


def inspect_bbga() -> tuple[dict, list[dict]]:
    folder = RAW / "amsterdam_bbga"
    data_path = folder / "bbga-latest-and-greatest.csv"
    metadata_path = folder / "metadata-latest-and-greatest.csv"
    rows = 0
    years: set[int] = set()
    codes: set[str] = set()
    variables: set[str] = set()
    with data_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            rows += 1
            try:
                years.add(int(row["jaar"]))
            except (ValueError, TypeError):
                pass
            codes.add(row["gebiedcode15"].strip())
            variables.add(row["variabele"].strip())

    indicators = []
    with metadata_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            indicators.append(
                {
                    "source": "Amsterdam O&S BBGA",
                    "dataset_id": "BBGA",
                    "table_title": "Basisbestand Gebieden Amsterdam",
                    "variable": row.get("Variabele", ""),
                    "theme": row.get("THEMA", ""),
                    "label": row.get("Label", ""),
                    "definition": row.get("Definitie", ""),
                    "unit": " ".join(x for x in (row.get("Rekeneenheid", ""), row.get("Symbool", "")) if x),
                    "decimals": row.get("format", ""),
                    "period": row.get("Peildatum", ""),
                    "source_detail": row.get("Bron", ""),
                    "geography": "Amsterdam: stadsdeel/GGW-gebied/wijk/buurt en overige indelingen",
                    "nonempty_rows": "",
                    "nonempty_amsterdam_rows": "",
                }
            )
    return (
        {
            "source": "Amsterdam O&S BBGA",
            "rows": rows,
            "columns": 4,
            "variables_in_data": len(variables),
            "metadata_indicators": len(indicators),
            "years_min_max": [min(years), max(years)] if years else [],
            "year_count": len(years),
            "unique_area_codes": len(codes),
            "sample_area_codes": sorted(codes)[:25],
            "file_bytes": data_path.stat().st_size,
        },
        indicators,
    )


def inspect_leefbaarometer() -> tuple[dict, list[dict]]:
    folder = RAW / "leefbaarometer_2024" / "uitgepakt_relevant"
    files = [p for p in folder.rglob("*.csv") if "__MACOSX" not in p.parts]
    summaries = []
    for path in sorted(files):
        rows = 0
        years: set[str] = set()
        codes: set[str] = set()
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            fields = reader.fieldnames or []
            code_field = next((f for f in ("bu_code", "wk_code", "gm_code") if f in fields), None)
            for row in reader:
                rows += 1
                if row.get("jaar"):
                    years.add(row["jaar"])
                if code_field and row.get(code_field):
                    codes.add(row[code_field])
        summaries.append(
            {
                "file": str(path.relative_to(ROOT)),
                "rows": rows,
                "columns": fields,
                "years": sorted(years),
                "unique_regions": len(codes),
                "file_bytes": path.stat().st_size,
            }
        )

    definitions = {
        "lbm": "Leefbaarheidsscore",
        "afw": "Afwijking van het landelijk gemiddelde",
        "fys": "Dimensie fysieke omgeving",
        "onv": "Dimensie overlast en onveiligheid",
        "soc": "Dimensie sociale samenhang",
        "vrz": "Dimensie voorzieningen",
        "won": "Dimensie woningvoorraad",
    }
    indicators = [
        {
            "source": "BZK Leefbaarometer 2024",
            "dataset_id": "LBM3-2024",
            "table_title": "Leefbaarometer scores 2002-2024",
            "variable": key,
            "theme": "Leefbaarheid",
            "label": label,
            "definition": "Zie officiële toelichting in het bronarchief en de Leefbaarometer-methodiek.",
            "unit": "modelscore",
            "decimals": "",
            "period": "2002-2024",
            "source_detail": "Ministerie van BZK, CC0",
            "geography": "buurt/wijk/gemeente",
            "nonempty_rows": "",
            "nonempty_amsterdam_rows": "",
        }
        for key, label in definitions.items()
    ]
    return {"source": "BZK Leefbaarometer 2024", "files": summaries}, indicators


def inspect_vektis_gemeentezorgspiegel() -> tuple[dict, list[dict]]:
    folder = RAW / "vektis_gemeentezorgspiegel"
    files = []
    for path in sorted(folder.glob("*.xlsx")):
        with zipfile.ZipFile(path) as archive:
            worksheet = next(name for name in archive.namelist() if name.startswith("xl/worksheets/sheet"))
            prefix = archive.open(worksheet).read(4096).decode("utf-8", errors="ignore")
            match = re.search(r'<dimension ref="([^"]+)"', prefix)
            dimension = match.group(1) if match else ""
            last_row_match = re.search(r"(\d+)$", dimension)
            rows = max(0, int(last_row_match.group(1)) - 1) if last_row_match else None
        files.append(
            {
                "file": str(path.relative_to(ROOT)),
                "rows_excluding_header": rows,
                "worksheet_dimension": dimension,
                "file_bytes": path.stat().st_size,
            }
        )

    categories = [
        "Hulp bij het huishouden - totaal",
        "Hulpmiddelen en diensten - totaal",
        "Ondersteuning thuis - begeleiding",
        "Ondersteuning thuis - dagbesteding",
        "Ondersteuning thuis - totaal",
        "Overig - overige maatwerkarrangementen",
        "Overig - totaal",
        "Totaal zorgdomein - exclusief verblijf en opvang",
        "Verblijf en opvang - beschermd wonen",
        "Verblijf en opvang - totaal",
    ]
    indicators = [
        {
            "source": "Vektis Gemeentezorgspiegel Wmo",
            "dataset_id": "GZS-WMO-2025",
            "table_title": "Wmo-cliënten naar maatwerkarrangement en leeftijd, 2019-2024",
            "variable": f"wmo_{index:02d}",
            "theme": "Wmo-maatwerkarrangementen",
            "label": category,
            "definition": "Aantal unieke Wmo-cliënten; minder dan 10 niet beschikbaar, overige aantallen afgerond op tientallen.",
            "unit": "aantal cliënten",
            "decimals": "0 (afgerond op tientallen)",
            "period": "2019-2024",
            "source_detail": "Vektis C.V.; eigen berekeningen in CBS-microdata-omgeving, project 3132.",
            "geography": "buurt/wijk/gemeente/VNG-ZN-regio/land; CBS-indeling 2024",
            "nonempty_rows": "",
            "nonempty_amsterdam_rows": "",
        }
        for index, category in enumerate(categories, start=1)
    ]
    summary = {
        "source": "Vektis Gemeentezorgspiegel Wmo",
        "title": "Wmo-cliënten naar maatwerkarrangement en leeftijd, 2019-2024",
        "period": "2019-2024",
        "boundary_year": 2024,
        "geography": ["buurt", "wijk", "gemeente", "VNG/ZN-regio", "land"],
        "care_categories": categories,
        "privacy": "Categorieën met minder dan 10 cliënten ontbreken; aantallen zijn afgerond op tientallen.",
        "files": files,
    }
    return summary, indicators


AMSTERDAM_SOURCE_SPECS = [
    {
        "slug": "amsterdam_maatschappelijke_voorzieningen",
        "source": "Gemeente Amsterdam maatschappelijke voorzieningen",
        "dataset_id": "AMS-MV",
        "title": "Voorzieningen op de kaart",
        "theme": "Aanbod zorg en welzijn",
        "definition": "Actuele inventaris van gemeentelijke maatschappelijke voorzieningen met domein, categorie, soort, adres en geometrie.",
        "period": "momentopname download 2026-07-10",
        "geography": "puntlocatie; koppelbaar aan buurt/wijk/GGW-gebied",
    },
    {
        "slug": "amsterdam_sportvoorzieningen",
        "source": "Gemeente Amsterdam sportvoorzieningen",
        "dataset_id": "AMS-SPORT",
        "title": "Sportvoorzieningen",
        "theme": "Bewegen en ontmoeting",
        "definition": "GeoJSON-lagen voor aanbieders en sportlocaties, waaronder sporthallen, gymzalen, velden, parken, openbare sportplekken, hardlooproutes en zwembaden.",
        "period": "momentopname download 2026-07-10",
        "geography": "punt-, lijn- en vlakgeometrie; koppelbaar aan buurt/wijk/GGW-gebied",
    },
    {
        "slug": "amsterdam_schoolgebouwen",
        "source": "Gemeente Amsterdam schoolgebouwen",
        "dataset_id": "AMS-SCHOOL",
        "title": "Schoolgebouwen en kengetallen",
        "theme": "Jeugd, onderwijs en voorzieningenplanning",
        "definition": "Gekoppelde tabellen voor accommodaties, instellingen, objecten, gebruik en kengetallen zoals leerlingaantallen, prognoses en ruimtebehoefte.",
        "period": "momentopname download 2026-07-10",
        "geography": "adres, stadsdeel en wijk; relaties via accommodatie-, instelling- en object-id",
    },
    {
        "slug": "amsterdam_nieuwbouwplannen",
        "source": "Gemeente Amsterdam nieuwbouwplannen",
        "dataset_id": "AMS-NB",
        "title": "Woningbouwplannen openbaar",
        "theme": "Demografische ontwikkeling en toekomstige vraag",
        "definition": "Openbare woningbouwplannen met planfase, aantallen woningen, segmenten en gebiedscodes; geschikt als vroegsignaal voor nieuwe vraag naar voorzieningen.",
        "period": "momentopname download 2026-07-10",
        "geography": "punt-/vlakgeometrie en buurt/wijk/GGW-gebied/stadsdeel",
    },
    {
        "slug": "amsterdam_gebieden",
        "source": "Gemeente Amsterdam gebiedsindelingen",
        "dataset_id": "AMS-GEBIED",
        "title": "Officiële gebiedsgrenzen",
        "theme": "Geografische referentie",
        "definition": "Officiële actuele GeoJSON-grenzen van buurten, wijken, stadsdelen en de 25 GGW-gebieden; te gebruiken als leidende kaartindeling in de tool.",
        "period": "momentopname download 2026-07-10",
        "geography": "buurt/wijk/GGW-gebied/stadsdeel",
    },
    {
        "slug": "amsterdam_ois_focusgebieden",
        "source": "Amsterdam O&S focusgebieden",
        "dataset_id": "AMS-OIS-FOCUS",
        "title": "Outcomemonitor focusgebieden",
        "theme": "Welzijn, inclusie en kansengelijkheid",
        "definition": "Indicatoren en tabellen voor Masterplan Zuidoost, Aanpak Noord en Samen Nieuw-West. Alleen gebruiken als referentie en niet als representatief beeld voor Amsterdam-Oost.",
        "period": "juni 2026 (metingen verschillen per indicator)",
        "geography": "focusgebieden en bijbehorende deelgebieden",
    },
    {
        "slug": "amsterdam_ois_veiligheidsindex",
        "source": "Amsterdam O&S veiligheidsindex",
        "dataset_id": "AMS-OIS-VI",
        "title": "Veiligheidsindex",
        "theme": "Veiligheid als welzijnscontext",
        "definition": "Index- en vergelijkingsbestanden met geregistreerde criminaliteit en veiligheidsindicatoren op deelgebiedsniveau. Niet interpreteren als directe gezondheids- of zorgvraag.",
        "period": "2026-1; onderliggende jaren variëren per indicator",
        "geography": "veiligheidsmonitorgebied/deelgebied",
    },
]


def inspect_xlsx(path: Path) -> dict:
    """Geef een compacte technische inhoudsopgave zonder Excel te muteren."""
    sheets = []
    with zipfile.ZipFile(path) as archive:
        workbook_xml = archive.read("xl/workbook.xml").decode("utf-8", errors="ignore")
        names = re.findall(r'<sheet[^>]* name="([^"]+)"', workbook_xml)
        worksheet_files = sorted(name for name in archive.namelist() if name.startswith("xl/worksheets/sheet"))
        for index, worksheet in enumerate(worksheet_files):
            prefix = archive.open(worksheet).read(4096).decode("utf-8", errors="ignore")
            match = re.search(r'<dimension ref="([^"]+)"', prefix)
            sheets.append({
                "name": names[index] if index < len(names) else worksheet,
                "dimension": match.group(1) if match else "",
            })
    return {"kind": "xlsx", "sheets": sheets}


def inspect_amsterdam_sources() -> tuple[list[dict], list[dict]]:
    summaries = []
    indicators = []
    for spec in AMSTERDAM_SOURCE_SPECS:
        folder = RAW / spec["slug"]
        files = []
        for path in sorted(p for p in folder.iterdir() if p.is_file()):
            suffix = path.suffix.lower()
            detail: dict = {
                "file": str(path.relative_to(ROOT)),
                "file_bytes": path.stat().st_size,
            }
            if suffix == ".csv":
                with path.open("r", encoding="utf-8-sig", newline="") as handle:
                    reader = csv.reader(handle)
                    fields = next(reader, [])
                    rows = sum(1 for _ in reader)
                detail.update({"kind": "csv", "rows_excluding_header": rows, "columns": fields})
            elif suffix == ".geojson":
                payload = json.loads(path.read_text(encoding="utf-8"))
                features = payload.get("features", [])
                fields = sorted({key for feature in features for key in (feature.get("properties") or {})})
                geometry_types = Counter(
                    (feature.get("geometry") or {}).get("type", "geen") for feature in features
                )
                detail.update({
                    "kind": "geojson",
                    "features": len(features),
                    "property_fields": fields,
                    "geometry_types": dict(geometry_types),
                })
            elif suffix == ".xlsx":
                detail.update(inspect_xlsx(path))
            files.append(detail)

        summaries.append({
            "source": spec["source"],
            "slug": spec["slug"],
            "title": spec["title"],
            "period": spec["period"],
            "geography": spec["geography"],
            "files": files,
        })
        indicators.append({
            "source": spec["source"],
            "dataset_id": spec["dataset_id"],
            "table_title": spec["title"],
            "variable": spec["slug"],
            "theme": spec["theme"],
            "label": spec["title"],
            "definition": spec["definition"],
            "unit": "zie bronvelden",
            "decimals": "",
            "period": spec["period"],
            "source_detail": "Gemeente Amsterdam open data / O&S; opgeslagen bronmoment 2026-07-10.",
            "geography": spec["geography"],
            "nonempty_rows": "",
            "nonempty_amsterdam_rows": "",
        })
    return summaries, indicators


def write_indicator_catalog(indicators: list[dict]) -> None:
    output = ROOT / "indicator_catalog.csv"
    fields = list(indicators[0].keys())
    with output.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(indicators)


def write_manifest(summary: list[dict]) -> None:
    files = []
    checksum_lines = []
    for path in sorted(p for p in RAW.rglob("*") if p.is_file() and not p.name.endswith(".part")):
        digest = sha256(path)
        rel = path.relative_to(ROOT).as_posix()
        files.append({"path": rel, "bytes": path.stat().st_size, "sha256": digest})
        checksum_lines.append(f"{digest}  {rel}")
    manifest = {
        "generated": datetime.now().astimezone().isoformat(timespec="seconds"),
        "file_count": len(files),
        "total_bytes": sum(item["bytes"] for item in files),
        "files": files,
        "dataset_summary": summary,
    }
    (ROOT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    (ROOT / "checksums.sha256").write_text("\n".join(checksum_lines) + "\n", encoding="utf-8")


def main() -> None:
    summaries = []
    indicators = []
    for name, slug in ODATA:
        summary, source_indicators = inspect_odata(name, slug)
        summaries.append(summary)
        indicators.extend(source_indicators)
    summary, source_indicators = inspect_bbga()
    summaries.append(summary)
    indicators.extend(source_indicators)
    summary, source_indicators = inspect_leefbaarometer()
    summaries.append(summary)
    indicators.extend(source_indicators)
    summary, source_indicators = inspect_vektis_gemeentezorgspiegel()
    summaries.append(summary)
    indicators.extend(source_indicators)
    source_summaries, source_indicators = inspect_amsterdam_sources()
    summaries.extend(source_summaries)
    indicators.extend(source_indicators)

    (ROOT / "technical_summary.json").write_text(
        json.dumps(summaries, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    write_indicator_catalog(indicators)
    write_manifest(summaries)
    print(f"Datasets: {len(summaries)}")
    print(f"Indicatoren in catalogus: {len(indicators)}")


if __name__ == "__main__":
    main()
