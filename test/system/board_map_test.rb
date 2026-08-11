require "application_system_test_case"

# Regression coverage for the single-pin centring bug: latitude landed ~13°
# away from the seeded value (longitude stayed exact) while a two-pin board
# was unaffected. Root cause, confirmed by instrumenting the controller
# directly in a real browser: the single-pin branch called setCenter and
# setZoom(14) as two SEPARATE camera moves, while the map still sat at its
# constructor's zoom: 1. At zoom 1 the world's rendered height (512 * 2^1 =
# 1024px) is smaller than most real map containers — including this suite's
# own 1400x1400 screen_size, which leaves ~1287px for the map. Mapbox GL's
# own "no room to pan past the poles" clamp then force-recentres latitude to
# the equator before setZoom(14) ever runs, and setZoom afterward does not
# recover the value that was already stomped. Longitude survives because
# that clamp is vertical-only — horizontal panning just wraps.
#
# fitBounds (2+ pins) never hits this: it derives center AND zoom together
# for the real bounds in one atomic camera move, so it's never briefly
# sitting at zoom 1 with a container taller than the world at that zoom. The
# fix makes the single-pin path atomic too (`jumpTo({ center, zoom: 14 })`)
# instead of two separate calls — this needs the real headless-Chrome/WebGL
# driver, not an integration test, because the corruption only exists inside
# Mapbox's own transform math, not in the JSON the server sends.
class BoardMapTest < ApplicationSystemTestCase
  test "a board with one located card centres the map on that card's coordinates" do
    board = boards(:one)
    cards(:one).update!(latitude: 51.5238, longitude: -0.0861, location_address: "Old St, London")

    sign_in_as(users(:one))
    visit "/boards/#{board.id}/map"

    assert_eventually(message: "map never centred on the single pin") do
      center = map_center
      center && (center["lat"] - 51.5238).abs < 0.001 && (center["lng"] - (-0.0861)).abs < 0.001
    end
  end

  test "a board with two located cards still fits both via fitBounds" do
    board = boards(:one)
    cards(:one).update!(latitude: 51.5138, longitude: -0.0986, location_address: "Angel, London")
    second = Card.create!(list: lists(:one), title: "Second located card",
                           latitude: 51.5053, longitude: -0.0754, location_address: "Farringdon, London")

    sign_in_as(users(:one))
    visit "/boards/#{board.id}/map"

    assert_eventually(message: "map never settled after fitBounds") { map_center.present? }
    center = map_center
    midpoint_lat = (51.5138 + 51.5053) / 2
    midpoint_lng = (-0.0986 + -0.0754) / 2
    assert_in_delta midpoint_lat, center["lat"], 0.02,
                     "fitBounds should centre roughly between the two pins, not on either one alone"
    assert_in_delta midpoint_lng, center["lng"], 0.02

    assert_equal 2, evaluate_script(<<~JS)
      document.querySelectorAll('.mapboxgl-marker').length
    JS
  ensure
    second&.destroy
  end

  test "a board with no located cards shows the empty state instead of a map" do
    board = boards(:two)
    cards(:two).update!(latitude: nil, longitude: nil)

    sign_in_as(users(:two))
    visit "/boards/#{board.id}/map"

    assert_text "No locations yet"
    assert_no_selector "[data-controller='board-map']"
  end

  private

  def map_center
    evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller="board-map"]')
        if (!el || !window.Stimulus) return null
        const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "board-map")
        if (!controller || !controller.map) return null
        const c = controller.map.getCenter()
        return { lat: c.lat, lng: c.lng }
      })()
    JS
  end
end
