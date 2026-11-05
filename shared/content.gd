extends RefCounted
## Local ROM identities only. Importability is separate from playable integration.
const ROMS = {
	"cobi": {"name": "Cobi's Journey (USA)", "platform": "GBC", "bytes": 4194304, "extension": "gbc", "sha256": "8e38a7420ef5239c7196aa4fd4b1499e65db2823e875bbf8241bb2199e766d4e", "playable": true},
	"iru": {"name": "Iru no Bouken (Japan)", "platform": "GBC", "bytes": 4194304, "extension": "gbc", "sha256": "1916208828ce85763d7ca03821eb17cec1a51d55cd80a36bd30a3ea653396a39", "playable": false},
	"caravan": {"name": "Caravan Heart (Japan)", "platform": "GBA", "bytes": 8388608, "extension": "gba", "sha256": "fb388539b95fdaf6009bad879e9bbb25955daf8d4d438486a9213d407b2b48ce", "playable": false}
}

static func identify(sha256: String) -> String:
	for id in ROMS:
		if ROMS[id].sha256 == sha256: return id
	return ""
