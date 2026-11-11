#!/usr/bin/env bash
# Creates the roadmap issues in this repo and adds them to your GitHub
# Projects board (https://github.com/users/paulmadojutimi94/projects/1).
#
# One-time setup:  gh auth login && gh auth refresh -s project
# Run:             ./scripts/seed_project_board.sh
set -euo pipefail

OWNER="paulmadojutimi94"
REPO="$OWNER/support-sense-"
PROJECT=1

add() {
  local title="$1" body="$2"
  url=$(gh issue create --repo "$REPO" --title "$title" --body "$body")
  gh project item-add "$PROJECT" --owner "$OWNER" --url "$url"
  echo "added: $title"
}

add "v1: BM25 ranker, confidence labels, feedback capture" \
    "Shipped. Dev top-1 98.4%, held-out 23.1%, 0 wrong High labels. See README."
add "Semantic re-ranker (NLEmbedding) for vocabulary mismatch" \
    "Held-out failures are synonym/paraphrase misses (binned→trash, run out of room→storage). Re-rank BM25 top-10 with on-device sentence embeddings. Success = held-out top-1 ≥ 60% with 0 wrong High."
add "Typo tolerance (edit distance ≤1 on unmatched terms)" \
    "'passwrd reset' only works via 'reset'. Add fuzzy match against the KB vocabulary."
add "Number/unit tokenisation (2TB vs 2 TB)" \
    "'how much is 2TB' returns nothing because the KB writes '2 TB'."
add "Per-query feedback instead of global article boost" \
    "Global votes can create popularity bias. Key feedback on (normalised query, article)."
add "Record 3-minute demo video" "Follow DEMO.md script."
add "Grow held-out set to 100 queries from real support tickets" \
    "Current held-out n=26 in-scope gives roughly ±16pp at 95% confidence; too wide to compare models."
