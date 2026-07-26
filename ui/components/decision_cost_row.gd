class_name DecisionCostRow
extends HFlowContainer

## Layout-only presenter for already typed metadata tokens. It neither parses
## prose nor infers costs from an action.

const MetaTokenScene := preload("res://ui/components/meta_token.tscn")

var _tokens: Array[Dictionary] = []


func present(tokens: Array[Dictionary]) -> void:
	_tokens.clear()
	for token: Dictionary in tokens:
		_tokens.append(token.duplicate(true))
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for token: Dictionary in _tokens:
		var token_view := MetaTokenScene.instantiate() as MetaToken
		add_child(token_view)
		token_view.present(token)
	visible = not _tokens.is_empty()
