"""Build-wide constants."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SITE_URL = "https://josie.lol"
PERSON_ID = f"{SITE_URL}/#person"

TEMPLATES_DIR = ROOT / "templates"
DATA_DIR = ROOT / "data"
BLOG_DIR = ROOT / "blog"
TALKS_DIR = ROOT / "talks"
OUTPUT_ROOT = ROOT
