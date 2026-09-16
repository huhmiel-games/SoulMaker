class_name SchemaUtil
extends RefCounted

## Shared character-class checks for schema-pattern fields (ids, sha256…).
## Char-level validation only: no RegEx dependency, deterministic everywhere.

const ID_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789_"
const SHA_CHARS := "0123456789abcdef"


static func matches_id(s: String) -> bool:
	if s.is_empty():
		return false
	for ch in s:
		if not ID_CHARS.contains(ch):
			return false
	return true


static func matches_sha256(s: String) -> bool:
	if s.length() != 64:
		return false
	for ch in s:
		if not SHA_CHARS.contains(ch):
			return false
	return true