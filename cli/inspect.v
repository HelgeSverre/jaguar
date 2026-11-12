module cli

import json
import loader

struct SegmentJson {
	name string
	addr string
	len  int
}

struct PlanJson {
	kind            string
	variant         string
	entry           string
	needs_cart_boot bool
	original_hash   string
	normalized_hash string
	normalizations  []string
	ambiguous       bool
	segments        []SegmentJson
	notes           []string
}

// plan_json renders a load plan for `inspect --json`.
fn plan_json(plan loader.LoadPlan) string {
	return json.encode_pretty(PlanJson{
		kind:            plan.kind.str()
		variant:         plan.variant
		entry:           '0x${plan.entry:06x}'
		needs_cart_boot: plan.needs_cart_boot
		original_hash:   plan.original_hash
		normalized_hash: plan.normalized_hash
		normalizations:  plan.normalizations
		ambiguous:       plan.ambiguous
		segments:        plan.segments.map(SegmentJson{
			name: it.name
			addr: '0x${it.addr:06x}'
			len:  it.data.len
		})
		notes:           plan.notes
	})
}
