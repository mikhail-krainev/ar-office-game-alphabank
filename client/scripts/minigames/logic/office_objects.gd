class_name OfficeObjects
extends RefCounted
## Objects for the "Find the object" task. Every target lists the labels that count as a hit. The
## web build recognizes objects with two stock MediaPipe models: the EfficientDet-Lite0 detector (COCO
## classes, e.g. "cup", "potted plant") and the EfficientNet-Lite0 classifier (ImageNet classes, e.g.
## "coffee mug", "wall clock"). No custom model is trained, so only things those classes cover are used.
## One object often produces several labels, so each target accepts a small group of them. Classifier
## labels are the first ImageNet name of a class ("ashcan" is a trash can, "switch" a light switch).

## Detector scores and classifier probabilities of a clearly visible object are usually above this.
const MIN_CONFIDENCE: float = 0.45


class Target:
	extends RefCounted

	var id: String
	var name_key: String
	var labels: PackedStringArray

	func _init(p_id: String, p_name_key: String, p_labels: PackedStringArray) -> void:
		id = p_id
		name_key = p_name_key
		labels = p_labels

	## Confidence of the best matching label in `labels`, or 0.0 when the object is not in the frame.
	func confidence_in(detected: Array[SensorModels.ObjectLabel]) -> float:
		var best: float = 0.0
		for label: SensorModels.ObjectLabel in detected:
			if labels.has(label.id) and label.confidence > best:
				best = label.confidence
		return best

	func is_recognized(detected: Array[SensorModels.ObjectLabel]) -> bool:
		return confidence_in(detected) >= MIN_CONFIDENCE


static func defaults() -> Array[Target]:
	return [
		# Workplace.
		Target.new("mug", "OBJ_MUG", PackedStringArray(["cup", "coffee mug"])),
		Target.new("plant", "OBJ_PLANT", PackedStringArray(["potted plant", "pot", "vase"])),
		Target.new("screen", "OBJ_SCREEN", PackedStringArray(["tv", "laptop", "monitor", "screen", "desktop computer", "television", "notebook"])),
		Target.new("chair", "OBJ_CHAIR", PackedStringArray(["chair", "folding chair", "rocking chair", "barber chair"])),
		Target.new("sofa", "OBJ_SOFA", PackedStringArray(["couch", "studio couch"])),
		Target.new("desk", "OBJ_DESK", PackedStringArray(["dining table", "desk"])),
		Target.new("clock", "OBJ_CLOCK", PackedStringArray(["clock", "wall clock", "analog clock", "digital clock"])),
		Target.new("phone", "OBJ_PHONE", PackedStringArray(["cell phone", "cellular telephone", "dial telephone"])),
		Target.new("keyboard", "OBJ_KEYBOARD", PackedStringArray(["keyboard", "computer keyboard", "typewriter keyboard"])),
		Target.new("mouse", "OBJ_MOUSE", PackedStringArray(["mouse"])),
		Target.new("papers", "OBJ_PAPERS", PackedStringArray(["book", "binder", "envelope", "menu", "book jacket", "comic book"])),
		Target.new("pen", "OBJ_PEN", PackedStringArray(["ballpoint", "fountain pen"])),
		Target.new("scissors", "OBJ_SCISSORS", PackedStringArray(["scissors"])),
		Target.new("glasses", "OBJ_GLASSES", PackedStringArray(["sunglasses", "sunglass"])),
		Target.new("bag", "OBJ_BAG", PackedStringArray(["backpack", "handbag", "suitcase", "purse", "mailbag", "plastic bag"])),
		Target.new("bottle", "OBJ_BOTTLE", PackedStringArray(["bottle", "water bottle", "pop bottle"])),
		Target.new("printer", "OBJ_PRINTER", PackedStringArray(["printer", "photocopier"])),
		Target.new("switch", "OBJ_SWITCH", PackedStringArray(["switch"])),
		Target.new("trash_can", "OBJ_TRASH_CAN", PackedStringArray(["ashcan"])),
		# Kitchen.
		Target.new("fridge", "OBJ_FRIDGE", PackedStringArray(["refrigerator"])),
		Target.new("microwave", "OBJ_MICROWAVE", PackedStringArray(["microwave"])),
		Target.new("coffee_machine", "OBJ_COFFEE_MACHINE", PackedStringArray(["espresso maker", "coffeepot"])),
		Target.new("sink", "OBJ_SINK", PackedStringArray(["sink", "washbasin"])),
		Target.new("dishes", "OBJ_DISHES", PackedStringArray(["bowl", "plate", "soup bowl"])),
		Target.new("cutlery", "OBJ_CUTLERY", PackedStringArray(["spoon", "fork", "knife", "wooden spoon"])),
		Target.new("paper_towel", "OBJ_PAPER_TOWEL", PackedStringArray(["paper towel", "toilet tissue"])),
	]


## Targets from admin panel data (a list of ids), or the default set when the list is empty.
static func from_ids(ids: Array) -> Array[Target]:
	if ids.is_empty():
		return defaults()
	var result: Array[Target] = []
	for target: Target in defaults():
		if ids.has(target.id):
			result.append(target)
	return result if not result.is_empty() else defaults()


## Every label the game can react to, for the desktop sensor emulator.
static func all_labels() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for target: Target in defaults():
		for label: String in target.labels:
			if not result.has(label):
				result.append(label)
	return result
