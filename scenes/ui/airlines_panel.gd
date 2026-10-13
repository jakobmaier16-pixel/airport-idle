class_name AirlinesPanel
extends PanelContainer
## Airlines and deals (design doc §10.1): signed airlines, open offers, and negotiating an offer.
## Player commands go through Airport (like hiring); the panel itself only shows state.

const REFRESH: float = 0.5
const ROW_FONT_SIZE: int = 22
const UNHAPPY_COLOR: Color = Color(1.0, 0.55, 0.45)
const OFFER_COLOR: Color = Color(1.0, 0.88, 0.45)
## How much one tap on − / + changes the fee (euros) and the flights per hour.
const FEE_STEP: float = 1.0
const FLIGHTS_STEP: int = 2
## How long "End deal" waits for the confirming second tap.
const CONFIRM_TIME: float = 3.0

## The offer being negotiated, or null while the list is shown.
var negotiating: AirlineOffer = null
## The terms the player proposes.
var fee: float = 0.0
var flights: int = 0

var _refresh_in: float = 0.0
# What the list shows, to rebuild it only when airlines or offers change (rebuilding under a
# finger would swallow the tap).
var _list_key: String = ""
var _row_labels: Array[Label] = []
var _offer_buttons: Array[Button] = []

@onready var _capacity_label: Label = $Content/CapacityLabel
@onready var _list_view: VBoxContainer = $Content/ListView
@onready var _negotiation_view: Control = $Content/NegotiationView
@onready var _airline_label: Label = $Content/NegotiationView/AirlineLabel
@onready var _pitch_label: Label = $Content/NegotiationView/PitchLabel
@onready var _fee_label: Label = $Content/NegotiationView/TermsRow/FeeLabel
@onready var _flights_label: Label = $Content/NegotiationView/TermsRow/FlightsLabel
@onready var _chance_label: Label = $Content/NegotiationView/ChanceLabel
@onready var _tone_buttons: Control = $Content/NegotiationView/ToneButtons
@onready var _counter_buttons: Control = $Content/NegotiationView/CounterButtons
@onready var _result_label: Label = $Content/NegotiationView/ResultLabel
@onready var _decline_button: Button = $Content/NegotiationView/NavButtons/DeclineButton


func _ready() -> void:
	visible = false
	$Content/CloseButton.pressed.connect(close)
	$Content/NegotiationView/TermsRow/FeeMinus.pressed.connect(_change_fee.bind(-FEE_STEP))
	$Content/NegotiationView/TermsRow/FeePlus.pressed.connect(_change_fee.bind(FEE_STEP))
	$Content/NegotiationView/TermsRow/FlightsMinus.pressed.connect(_change_flights.bind(-FLIGHTS_STEP))
	$Content/NegotiationView/TermsRow/FlightsPlus.pressed.connect(_change_flights.bind(FLIGHTS_STEP))
	$Content/NegotiationView/ToneButtons/FirmButton.pressed.connect(_propose.bind(AirlineType.Tone.FIRM))
	$Content/NegotiationView/ToneButtons/FriendlyButton.pressed.connect(_propose.bind(AirlineType.Tone.FRIENDLY))
	$Content/NegotiationView/ToneButtons/FlexibleButton.pressed.connect(_propose.bind(AirlineType.Tone.FLEXIBLE))
	$Content/NegotiationView/CounterButtons/SignButton.pressed.connect(_sign_counter)
	$Content/NegotiationView/CounterButtons/DeclineCounterButton.pressed.connect(_decline)
	$Content/NegotiationView/NavButtons/BackButton.pressed.connect(show_list)
	_decline_button.pressed.connect(_decline)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_in -= delta
	if _refresh_in <= 0.0:
		_refresh_in = REFRESH
		_refresh()


func open() -> void:
	visible = true
	show_list()


func close() -> void:
	visible = false
	negotiating = null


## Shows signed airlines and open offers.
func show_list() -> void:
	negotiating = null
	_negotiation_view.visible = false
	_list_view.visible = true
	_capacity_label.visible = true
	_list_key = ""
	_refresh()


## Opens the negotiation for `offer`, starting from the airline's own terms.
func negotiate(offer: AirlineOffer) -> void:
	negotiating = offer
	fee = offer.fee
	flights = offer.flights_per_hour
	_list_view.visible = false
	_capacity_label.visible = false
	_negotiation_view.visible = true
	_result_label.text = ""
	var type := offer.type
	_airline_label.text = "%s · %s · asks for %d flights/h at %s per passenger" % [
		type.display_name, type.route, offer.flights_per_hour, Economy.format(offer.fee)]
	_pitch_label.text = "\"%s\"" % type.pitch
	_update_negotiation()


func _refresh() -> void:
	if negotiating != null:
		if not Airport.airlines.offers.has(negotiating):
			# Expired while the player was thinking.
			_result_label.text = "The offer has expired."
			_tone_buttons.visible = false
			_counter_buttons.visible = false
			_decline_button.visible = false
		return
	_update_list()


func _update_list() -> void:
	var airlines := Airport.airlines
	var gates := Airport.passenger_flow.usable_gates().size()
	var terminals := Airport.passenger_flow.usable_cargo_terminals().size()
	var cargo := 0
	for airline in airlines.signed:
		if airline.type.cargo:
			cargo += airline.flights_per_hour
	var text := "Gate capacity: %d flights/h (%d gates)" % [gates * _gate_flights_per_hour(), gates]
	if terminals > 0 or cargo > 0:
		text += ", cargo %d/h" % (terminals * _gate_flights_per_hour())
	text += "   ·   Signed: %d flights/h" % (airlines.signed_flights_per_hour() - cargo)
	if cargo > 0:
		text += " + %d cargo" % cargo
	_capacity_label.text = text

	var key := ""
	for airline in airlines.signed:
		key += "s" + airline.type.id
	for offer in airlines.offers:
		key += "o" + offer.type.id + str(offer.is_counter)
	if key != _list_key:
		_list_key = key
		_rebuild_list()
	for i in airlines.signed.size():
		var airline := airlines.signed[i]
		_row_labels[i].text = "%s · %s · %d flights/h · %s per passenger · happy %d %%" % [
			airline.type.display_name, airline.type.route, airline.flights_per_hour,
			Economy.format(airline.fee), roundi(airline.happiness)]
		_row_labels[i].add_theme_color_override(&"font_color", UNHAPPY_COLOR if airline.happiness < Airlines.COMPLAIN_BELOW else Color.WHITE)
	for i in airlines.offers.size():
		var offer := airlines.offers[i]
		var seconds := ceili(offer.expires_in)
		_offer_buttons[i].text = "Offer: %s · %s · %d flights/h · %s%s · %d:%02d left ›" % [
			offer.type.display_name, offer.type.route, offer.flights_per_hour, Economy.format(offer.fee),
			" (counter-offer)" if offer.is_counter else "", seconds / 60, seconds % 60]


func _rebuild_list() -> void:
	for child in _list_view.get_children():
		_list_view.remove_child(child)
		child.queue_free()
	_row_labels.clear()
	_offer_buttons.clear()
	var airlines := Airport.airlines
	if airlines.signed.is_empty():
		_add_label("No airline flies here. Wait for an offer.")
	for airline in airlines.signed:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override(&"font_size", ROW_FONT_SIZE)
		row.add_child(label)
		var end_button := Button.new()
		end_button.text = "End deal"
		end_button.custom_minimum_size = Vector2(150, 56)
		end_button.focus_mode = Control.FOCUS_NONE
		end_button.add_theme_font_size_override(&"font_size", 20)
		end_button.pressed.connect(_on_end_pressed.bind(end_button, airline))
		row.add_child(end_button)
		_list_view.add_child(row)
		_row_labels.append(label)
	if airlines.offers.is_empty():
		_add_label("No open offers. Airlines make offers every few minutes; better ratings attract bigger airlines.")
	for offer in airlines.offers:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 64)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override(&"font_size", 20)
		button.add_theme_color_override(&"font_color", OFFER_COLOR)
		button.pressed.connect(func() -> void:
			if offer.is_counter:
				negotiate(offer)
				_show_counter()
			else:
				negotiate(offer))
		_list_view.add_child(button)
		_offer_buttons.append(button)


func _add_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(770, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", ROW_FONT_SIZE)
	label.add_theme_color_override(&"font_color", Color(0.75, 0.78, 0.82))
	_list_view.add_child(label)


func _on_end_pressed(button: Button, airline: Airline) -> void:
	if button.text != "Tap again":
		button.text = "Tap again"
		# A method, not a lambda: the connection ends with the panel, and a lambda holding the
		# button would complain once the button is gone.
		get_tree().create_timer(CONFIRM_TIME).timeout.connect(_disarm_end_button.bind(button))
		return
	Airport.end_airline_deal(airline)
	_list_key = ""
	_refresh()


func _disarm_end_button(button: Button) -> void:
	if is_instance_valid(button):
		button.text = "End deal"


func _change_fee(step: float) -> void:
	fee = clampf(fee + step, Airlines.FEE_MIN, Airlines.FEE_MAX)
	_update_negotiation()


func _change_flights(step: int) -> void:
	flights = clampi(flights + step, Airlines.FLIGHTS_MIN, negotiating.flights_per_hour)
	_update_negotiation()


func _update_negotiation() -> void:
	_fee_label.text = "%s per passenger" % Economy.format(fee)
	_flights_label.text = "%d flights/h" % flights
	_tone_buttons.visible = true
	_counter_buttons.visible = false
	_decline_button.visible = true
	# The best of the three tones would be cheating: show the chance before the tone is chosen.
	var neutral := _neutral_tone(negotiating.type)
	var chance := Airport.airlines.chance(negotiating, fee, flights, neutral, Airport.stars())
	_chance_label.text = "Chance they agree: about %d %% (the right tone helps)" % roundi(chance * 100.0)


func _propose(tone: AirlineType.Tone) -> void:
	var offer := negotiating
	var answer := Airport.propose_airline_deal(offer, fee, flights, tone)
	match answer:
		Airlines.Answer.ACCEPTED:
			_result_label.text = "%s signed: %d flights/h at %s per passenger." % [offer.type.display_name, flights, Economy.format(fee)]
			_tone_buttons.visible = false
			_decline_button.visible = false
		Airlines.Answer.COUNTER:
			_show_counter()
		Airlines.Answer.REJECTED:
			_result_label.text = "%s walked away. They won't make a new offer for a while." % offer.type.display_name
			_tone_buttons.visible = false
			_decline_button.visible = false


func _show_counter() -> void:
	var offer := negotiating
	_result_label.text = "\"We can't do that. Our final offer: %d flights/h at %s per passenger.\"" % [offer.flights_per_hour, Economy.format(offer.fee)]
	_fee_label.text = "%s per passenger" % Economy.format(offer.fee)
	_flights_label.text = "%d flights/h" % offer.flights_per_hour
	_chance_label.text = "Counter-offer: sign it or decline."
	_tone_buttons.visible = false
	_decline_button.visible = false
	_counter_buttons.visible = true


func _sign_counter() -> void:
	var offer := negotiating
	if Airport.accept_airline_counter(offer) != null:
		_result_label.text = "%s signed: %d flights/h at %s per passenger." % [offer.type.display_name, offer.flights_per_hour, Economy.format(offer.fee)]
	_counter_buttons.visible = false


func _decline() -> void:
	Airport.decline_airline_offer(negotiating)
	show_list()


# The tone the airline neither likes nor dislikes.
static func _neutral_tone(type: AirlineType) -> AirlineType.Tone:
	for tone: AirlineType.Tone in [AirlineType.Tone.FIRM, AirlineType.Tone.FRIENDLY, AirlineType.Tone.FLEXIBLE]:
		if tone != type.likes and tone != type.dislikes:
			return tone
	return AirlineType.Tone.FRIENDLY


static func _gate_flights_per_hour() -> int:
	return roundi(3600.0 / FlightSchedule.INTERVAL)
