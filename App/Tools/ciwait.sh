sha=$1
while true; do
  r=$(curl -s "https://api.github.com/repos/1325ilya/BetterThanBox/actions/runs?per_page=10" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for x in d.get('workflow_runs',[]):
    if x['head_sha'].startswith('$sha'):
        print(x['status'],x.get('conclusion'),x['id']); break
")
  case "$r" in completed*) echo "$sha $r"; exit 0;; esac
  sleep 60
done
