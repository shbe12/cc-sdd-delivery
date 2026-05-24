if Rails.env.test?
  Geocoder.configure(lookup: :test, ip_lookup: :test)
  Geocoder::Lookup::Test.set_default_stub(
    [{ "coordinates" => [19.4326, -99.1332], "address" => "Ciudad de México, CDMX, México" }]
  )
else
  Geocoder.configure(
    lookup: :mapbox,
    api_key: ENV["MAPBOX_API_KEY"],
    units: :km,
    timeout: 5
  )
end
