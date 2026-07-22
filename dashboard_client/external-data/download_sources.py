"""Download geselecteerde open databronnen voor zorg, welzijn en gezondheid.

De OData-downloads worden als CSV opgeslagen, met alle officiële metadata-
collecties daarnaast als JSON. Bestaande bestanden worden standaard niet
opnieuw opgehaald; gebruik --force om ze te vervangen.
"""

from __future__ import annotations

import argparse
import csv
import itertools
import json
import shutil
import sys
import time
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"
USER_AGENT = "Dynamo-data-inventarisatie/1.0 (open-data research)"
PAGE_SIZE = 10_000


ODATA_DATASETS = [
    {
        "slug": "rivm_beweegvriendelijke_omgeving_50143NED",
        "base": "https://dataderden.cbs.nl/ODataApi/OData/50143NED",
        "filter": None,
        "note": "Landelijke totaal- en deelscores beweegvriendelijke omgeving, gemeenten, wijken en buurten, 2024.",
    },
    {
        "slug": "rivm_gezondheid_wijk_buurt_50150NED",
        "base": "https://dataderden.cbs.nl/ODataApi/OData/50150NED",
        "filter": "Leeftijd eq '20300' and Marges eq 'MW00000'",
        "note": "18 jaar of ouder; centrale schatting. Leeftijdsubgroepen en 95%-intervallen staan in de API-metadata.",
    },
    {
        "slug": "rivm_regiobeeld_wijk_buurt_50149NED",
        "base": "https://dataderden.cbs.nl/ODataApi/OData/50149NED",
        "filter": None,
        "partition": ["Perioden"],
        "note": "Alle cijfersoorten, gebieden en jaren; vooral zorgkosten en aantallen patienten op wijk-/buurtniveau.",
    },
    {
        "slug": "cbs_ses_woa_86296NED",
        "base": "https://opendata.cbs.nl/ODataApi/OData/86296NED",
        "filter": None,
        "partition": ["Perioden"],
        "note": "SES-WOA en deelscores, indeling 2025, verslagjaren 2014-2024.",
    },
    {
        "slug": "cbs_nabijheid_voorzieningen_86270NED",
        "base": "https://opendata.cbs.nl/ODataApi/OData/86270NED",
        "filter": None,
        "note": "Afstanden en aantallen voorzieningen, wijk en buurt, verslagjaar 2025.",
    },
    {
        "slug": "cbs_sociaal_domein_85994NED",
        "base": "https://opendata.cbs.nl/ODataApi/OData/85994NED",
        "filter": "Perioden eq '2024JJ00'",
        "partition": ["AantalVoorzieningen", "SoortVoorzieningSociaalDomein"],
        "note": "Definitieve jaarcijfers 2024; clienten/huishoudens naar combinatie van sociaal-domeinvoorzieningen, wijkniveau.",
    },
    {
        "slug": "cbs_wmo_type_86158NED",
        "base": "https://opendata.cbs.nl/ODataApi/OData/86158NED",
        "filter": "Perioden eq '2025JJ00'",
        "partition": ["TypeMaatwerkvoorziening"],
        "note": "Voorlopige jaarcijfers 2025; Wmo-clienten naar type maatwerkvoorziening, wijkniveau.",
    },
    {
        "slug": "cbs_jeugdzorg_wijken_86204NED",
        "base": "https://opendata.cbs.nl/ODataApi/OData/86204NED",
        "filter": "Perioden eq '2025JJ00'",
        "partition": ["Vormen"],
        "note": "Voorlopige jaarcijfers 2025; jeugdzorg naar vorm, leeftijd en huishoudsituatie, wijkniveau.",
    },
]


DIRECT_FILES = [
    {
        "slug": "vektis_gemeentezorgspiegel",
        "url": "https://www.vektis.nl/uploads/Gemeentezorgspiegel/Publicatie_microdata/wmo_cijfers_gzs_buurt_alle_leeftijden_publicatie_2025.xlsx",
        "filename": "wmo_cijfers_gzs_buurt_alle_leeftijden_publicatie_2025.xlsx",
    },
    {
        "slug": "vektis_gemeentezorgspiegel",
        "url": "https://www.vektis.nl/uploads/Gemeentezorgspiegel/Publicatie_microdata/wmo_cijfers_gzs_buurt_leeftijdscategorieen_publicatie_2025.xlsx",
        "filename": "wmo_cijfers_gzs_buurt_leeftijdscategorieen_publicatie_2025.xlsx",
    },
    {
        "slug": "vektis_gemeentezorgspiegel",
        "url": "https://www.vektis.nl/uploads/Gemeentezorgspiegel/Publicatie_microdata/wmo_cijfers_gzs_wijk_gemeente_regio_land_publicatie_2025.xlsx",
        "filename": "wmo_cijfers_gzs_wijk_gemeente_regio_land_publicatie_2025.xlsx",
    },
    {
        "slug": "vektis_gemeentezorgspiegel",
        "url": "https://www.vektis.nl/uploads/Gemeentezorgspiegel/Publicatie_microdata/wmo_cijfers_gzs_publicatie_2025.xlsx",
        "filename": "wmo_cijfers_gzs_publicatie_2025.xlsx",
    },
    {
        "slug": "amsterdam_bbga",
        "url": "https://onderzoek.amsterdam.nl/static/dashboard-kerncijfers/data/download/bbga-latest-and-greatest.csv",
        "filename": "bbga-latest-and-greatest.csv",
    },
    {
        "slug": "amsterdam_bbga",
        "url": "https://onderzoek.amsterdam.nl/static/dashboard-kerncijfers/data/download/metadata-latest-and-greatest.csv",
        "filename": "metadata-latest-and-greatest.csv",
    },
    {
        "slug": "amsterdam_bbga",
        "url": "https://onderzoek.amsterdam.nl/static/dashboard-kerncijfers/data/download/bbga-std-latest-and-greatest.csv",
        "filename": "bbga-std-latest-and-greatest.csv",
    },
    {
        "slug": "amsterdam_bbga",
        "url": "https://onderzoek.amsterdam.nl/static/dashboard-kerncijfers/data/download/bbga-latest-and-greatest.xlsx",
        "filename": "bbga-latest-and-greatest.xlsx",
    },
    {
        "slug": "leefbaarometer_2024",
        "url": "https://www.leefbaarometer.nl/resources/open-data-leefbaarometer-meting-2024.zip",
        "filename": "open-data-leefbaarometer-meting-2024.zip",
    },
    {
        "slug": "bron_documentatie",
        "url": "https://www.vektis.nl/uploads/Docs%20per%20pagina/Open%20Data%20Bestanden/2023/Bijsluiter%20bij%20de%20Vektis%20Open%20Databestanden%20Zorgverzekeringswet%202011%20-%202023%20.pdf",
        "filename": "vektis-bijsluiter-open-data-zvw-2011-2023.pdf",
    },
    {
        "slug": "bron_documentatie",
        "url": "https://ggdgezondheidinbeeld.nl/handlers/ballroom.ashx?function=download&id=122",
        "filename": "ggd-amsterdam-gezondheid-in-beeld-gebruikershandleiding.pdf",
    },
    # Actuele gemeentelijke, ruimtelijk koppelbare Amsterdamse bronlagen.
    {
        "slug": "amsterdam_maatschappelijke_voorzieningen",
        "url": "https://api.data.amsterdam.nl/v1/maatschappelijke_voorzieningen/voorzieningen_op_de_kaart?_format=csv",
        "filename": "voorzieningen_op_de_kaart.csv",
    },
    {
        "slug": "amsterdam_maatschappelijke_voorzieningen",
        "url": "https://api.data.amsterdam.nl/v1/maatschappelijke_voorzieningen/voorzieningen_op_de_kaart?_format=geojson",
        "filename": "voorzieningen_op_de_kaart.geojson",
    },
    {
        "slug": "amsterdam_sportvoorzieningen",
        "url": "https://api.data.amsterdam.nl/v1/sport/aanbieder?_format=geojson",
        "filename": "aanbieder.geojson",
    },
    {
        "slug": "amsterdam_sportvoorzieningen",
        "url": "https://api.data.amsterdam.nl/v1/sport/gymzaal?_format=geojson",
        "filename": "gymzaal.geojson",
    },
    {
        "slug": "amsterdam_sportvoorzieningen",
        "url": "https://api.data.amsterdam.nl/v1/sport/hal?_format=geojson",
        "filename": "hal.geojson",
    },
    {
        "slug": "amsterdam_sportvoorzieningen",
        "url": "https://api.data.amsterdam.nl/v1/sport/hardlooproute?_format=geojson",
        "filename": "hardlooproute.geojson",
    },
    {
        "slug": "amsterdam_sportvoorzieningen",
        "url": "https://api.data.amsterdam.nl/v1/sport/openbaresportplek?_format=geojson",
        "filename": "openbare_sportplek.geojson",
    },
    {
        "slug": "amsterdam_sportvoorzieningen",
        "url": "https://api.data.amsterdam.nl/v1/sport/park?_format=geojson",
        "filename": "park.geojson",
    },
    {
        "slug": "amsterdam_sportvoorzieningen",
        "url": "https://api.data.amsterdam.nl/v1/sport/veld?_format=geojson",
        "filename": "veld.geojson",
    },
    {
        "slug": "amsterdam_sportvoorzieningen",
        "url": "https://api.data.amsterdam.nl/v1/sport/zwembad?_format=geojson",
        "filename": "zwembad.geojson",
    },
    {
        "slug": "amsterdam_schoolgebouwen",
        "url": "https://api.data.amsterdam.nl/v1/schoolgebouwen/accommodatie?_format=csv",
        "filename": "accommodatie.csv",
    },
    {
        "slug": "amsterdam_schoolgebouwen",
        "url": "https://api.data.amsterdam.nl/v1/schoolgebouwen/instelling?_format=csv",
        "filename": "instelling.csv",
    },
    {
        "slug": "amsterdam_schoolgebouwen",
        "url": "https://api.data.amsterdam.nl/v1/schoolgebouwen/kengetallen?_format=csv",
        "filename": "kengetallen.csv",
    },
    {
        "slug": "amsterdam_schoolgebouwen",
        "url": "https://api.data.amsterdam.nl/v1/schoolgebouwen/gebruik?_format=csv",
        "filename": "gebruik.csv",
    },
    {
        "slug": "amsterdam_schoolgebouwen",
        "url": "https://api.data.amsterdam.nl/v1/schoolgebouwen/object?_format=csv",
        "filename": "object.csv",
    },
    {
        "slug": "amsterdam_nieuwbouwplannen",
        "url": "https://api.data.amsterdam.nl/v1/nieuwbouwplannen/woningbouwplannen_openbaar?_format=csv",
        "filename": "woningbouwplannen_openbaar.csv",
    },
    {
        "slug": "amsterdam_nieuwbouwplannen",
        "url": "https://api.data.amsterdam.nl/v1/nieuwbouwplannen/woningbouwplannen_openbaar?_format=geojson",
        "filename": "woningbouwplannen_openbaar.geojson",
    },
    {
        "slug": "amsterdam_gebieden",
        "url": "https://api.data.amsterdam.nl/v1/gebieden/buurten?_format=geojson",
        "filename": "buurten.geojson",
    },
    {
        "slug": "amsterdam_gebieden",
        "url": "https://api.data.amsterdam.nl/v1/gebieden/wijken?_format=geojson",
        "filename": "wijken.geojson",
    },
    {
        "slug": "amsterdam_gebieden",
        "url": "https://api.data.amsterdam.nl/v1/gebieden/ggwgebieden?_format=geojson",
        "filename": "ggwgebieden.geojson",
    },
    {
        "slug": "amsterdam_gebieden",
        "url": "https://api.data.amsterdam.nl/v1/gebieden/stadsdelen?_format=geojson",
        "filename": "stadsdelen.geojson",
    },
    # O&S-bestanden zijn contextuele benchmarklagen; focusgebieden liggen niet in Oost.
    {
        "slug": "amsterdam_ois_focusgebieden",
        "url": "https://cms.onderzoek-en-statistiek.nl/uploads/tabel_overzicht_indicatoren_focusgebieden_juni_26_3bee76ea76.xlsx",
        "filename": "tabel_overzicht_indicatoren_focusgebieden_juni_2026.xlsx",
    },
    {
        "slug": "amsterdam_ois_focusgebieden",
        "url": "https://cms.onderzoek-en-statistiek.nl/uploads/tabel_alle_data_Masterplan_Zuidoost_juni_2026_e10dd4efe7.xlsx",
        "filename": "tabel_alle_data_masterplan_zuidoost_juni_2026.xlsx",
    },
    {
        "slug": "amsterdam_ois_focusgebieden",
        "url": "https://cms.onderzoek-en-statistiek.nl/uploads/tabel_alle_data_Aanpak_Noord_juni_2026_d633371216.xlsx",
        "filename": "tabel_alle_data_aanpak_noord_juni_2026.xlsx",
    },
    {
        "slug": "amsterdam_ois_focusgebieden",
        "url": "https://cms.onderzoek-en-statistiek.nl/uploads/tabel_alle_data_Samen_Nieuw_West_juni_2026_d8d652b209.xlsx",
        "filename": "tabel_alle_data_samen_nieuw_west_juni_2026.xlsx",
    },
    {
        "slug": "amsterdam_ois_veiligheidsindex",
        "url": "https://cms.onderzoek-en-statistiek.nl/uploads/veiligheidsindex_2026_1_84ebd334de.xlsx",
        "filename": "veiligheidsindex_2026_1.xlsx",
    },
    {
        "slug": "amsterdam_ois_veiligheidsindex",
        "url": "https://cms.onderzoek-en-statistiek.nl/uploads/vergelijking_2026_1_ebce5453c6.xlsx",
        "filename": "veiligheidsindex_vergelijking_2026_1.xlsx",
    },
]


def request_json(url: str, retries: int = 4) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=180) as response:
                return json.load(response)
        except Exception:
            if attempt + 1 == retries:
                raise
            time.sleep(2 ** attempt)
    raise RuntimeError("onbereikbaar")


def service_collections(base: str) -> list[str]:
    service = request_json(base)
    return [item["name"] for item in service.get("value", [])]


def save_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".part")
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    temp.replace(path)


def download_metadata(dataset: dict, force: bool) -> None:
    target = RAW / dataset["slug"] / "metadata"
    target.mkdir(parents=True, exist_ok=True)
    collections = service_collections(dataset["base"])
    for collection in collections:
        if collection in {"TypedDataSet", "UntypedDataSet"}:
            continue
        output = target / f"{collection}.json"
        if output.exists() and not force:
            continue
        url = f"{dataset['base']}/{collection}?$top=100000"
        payload = request_json(url)
        save_json(output, payload.get("value", []))

    save_json(
        RAW / dataset["slug"] / "selection.json",
        {
            "base_url": dataset["base"],
            "collection": "TypedDataSet",
            "filter": dataset["filter"],
            "note": dataset["note"],
        },
    )


def download_odata_csv(dataset: dict, force: bool) -> None:
    target = RAW / dataset["slug"]
    target.mkdir(parents=True, exist_ok=True)
    output = target / "data.csv"
    if output.exists() and not force:
        print(f"  bestaand: {output.relative_to(ROOT)}")
        return

    temp = output.with_suffix(".csv.part")
    if temp.exists():
        temp.unlink()

    total = 0
    fieldnames: list[str] | None = None
    with temp.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = None
        partition_names = dataset.get("partition", [])
        if partition_names:
            key_lists = []
            for partition_name in partition_names:
                payload = request_json(f"{dataset['base']}/{partition_name}?$top=100000")
                key_lists.append([str(row["Key"]) for row in payload.get("value", [])])
            partitions = list(itertools.product(*key_lists))
        else:
            partitions = [tuple()]

        for partition_keys in partitions:
            filters = []
            if dataset["filter"]:
                filters.append(dataset["filter"])
            for partition_name, partition_key in zip(partition_names, partition_keys):
                escaped = partition_key.replace("'", "''")
                filters.append(f"{partition_name} eq '{escaped}'")
            params = {"$top": "9999"}
            if filters:
                params["$filter"] = " and ".join(filters)
            query = urllib.parse.urlencode(params, quote_via=urllib.parse.quote)
            url = f"{dataset['base']}/TypedDataSet?{query}"
            try:
                rows = request_json(url).get("value", [])
            except Exception:
                # De CBS API geeft bij een te grote selectie soms alleen een
                # generieke HTTP-fout terug. Dezelfde partitie kan dan via de
                # pagineerbare ODataFeed alsnog volledig worden opgehaald.
                rows = []

            # Een volle API-pagina kan stil zijn afgekapt. Gebruik dan de
            # ODataFeed voor dezelfde beperkte partitie en pagineer met $skip.
            use_feed = len(rows) >= 9999 or not rows
            skip = 0
            while True:
                if use_feed:
                    feed_base = dataset["base"].replace("/ODataApi/", "/ODataFeed/")
                    feed_params = {"$top": "5000", "$skip": str(skip), "$format": "json"}
                    if filters:
                        feed_params["$filter"] = " and ".join(filters)
                    feed_query = urllib.parse.urlencode(feed_params, quote_via=urllib.parse.quote)
                    rows = request_json(f"{feed_base}/TypedDataSet?{feed_query}").get("value", [])
                if not rows:
                    break
                if writer is None:
                    fieldnames = list(rows[0].keys())
                    writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
                    writer.writeheader()
                writer.writerows(rows)
                total += len(rows)
                labels = ", ".join(
                    f"{name}={key.strip()}" for name, key in zip(partition_names, partition_keys)
                )
                suffix = f" ({labels})" if labels else ""
                print(f"  {dataset['slug']}: {total:,} rijen{suffix}", flush=True)
                if not use_feed or len(rows) < 5000:
                    break
                skip += len(rows)

    if total == 0:
        temp.unlink(missing_ok=True)
        raise RuntimeError(f"Geen rijen ontvangen voor {dataset['slug']} (filter: {dataset['filter']})")
    temp.replace(output)


def download_file(item: dict, force: bool) -> Path:
    target = RAW / item["slug"] / item["filename"]
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and not force:
        print(f"  bestaand: {target.relative_to(ROOT)}")
        return target
    temp = target.with_suffix(target.suffix + ".part")
    req = urllib.request.Request(item["url"], headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=600) as response, temp.open("wb") as handle:
        length = int(response.headers.get("Content-Length", "0") or 0)
        copied = 0
        while True:
            block = response.read(1024 * 1024)
            if not block:
                break
            handle.write(block)
            copied += len(block)
            if copied % (50 * 1024 * 1024) < len(block):
                if length:
                    print(f"  {item['filename']}: {copied / 1024**2:.0f}/{length / 1024**2:.0f} MB", flush=True)
                else:
                    print(f"  {item['filename']}: {copied / 1024**2:.0f} MB", flush=True)
    temp.replace(target)
    return target


def extract_relevant_leefbaarometer(zip_path: Path, force: bool) -> None:
    extract_dir = zip_path.parent / "uitgepakt_relevant"
    if extract_dir.exists() and force:
        shutil.rmtree(extract_dir)
    extract_dir.mkdir(parents=True, exist_ok=True)
    keywords = ("buurt", "wijk", "gemeente", "toelicht", "metadata", "lees")
    with zipfile.ZipFile(zip_path) as archive:
        names = archive.namelist()
        save_json(zip_path.parent / "archive_contents.json", names)
        selected = [name for name in names if any(k in name.lower() for k in keywords)]
        if not selected:
            raise RuntimeError("Geen wijk-/buurtbestanden herkend in Leefbaarometer-archief")
        for name in selected:
            destination = extract_dir / name
            if destination.exists() and not force:
                continue
            archive.extract(name, extract_dir)
    print(f"  Leefbaarometer: {len(selected)} relevante archiefitems uitgepakt")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true", help="bestaande downloads vervangen")
    parser.add_argument("--skip-large", action="store_true", help="Leefbaarometer ZIP overslaan")
    args = parser.parse_args()

    RAW.mkdir(parents=True, exist_ok=True)
    for dataset in ODATA_DATASETS:
        print(f"OData: {dataset['slug']}")
        download_metadata(dataset, args.force)
        download_odata_csv(dataset, args.force)

    leefbaarometer_zip: Path | None = None
    for item in DIRECT_FILES:
        if args.skip_large and item["slug"] == "leefbaarometer_2024":
            continue
        print(f"Bestand: {item['filename']}")
        path = download_file(item, args.force)
        if item["slug"] == "leefbaarometer_2024":
            leefbaarometer_zip = path

    if leefbaarometer_zip:
        extract_relevant_leefbaarometer(leefbaarometer_zip, args.force)

    print("Downloads voltooid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
