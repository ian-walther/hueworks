defmodule Hueworks.Location.PostalCodeLookupTest do
  use ExUnit.Case, async: false

  alias Hueworks.Location.PostalCodeLookup

  setup do
    previous_client = Application.get_env(:hueworks, :postal_code_http_client)
    previous_response = Application.get_env(:hueworks, :postal_code_http_response)

    Application.put_env(:hueworks, :postal_code_http_client, __MODULE__.HttpClient)

    on_exit(fn ->
      restore_env(:postal_code_http_client, previous_client)
      restore_env(:postal_code_http_response, previous_response)
    end)

    :ok
  end

  test "returns coordinates and a human-readable place for a postal code" do
    respond_with(
      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body:
           Jason.encode!(%{
             "country" => "United States",
             "country abbreviation" => "US",
             "post code" => "90210",
             "places" => [
               %{
                 "place name" => "Beverly Hills",
                 "state" => "California",
                 "latitude" => "34.0901",
                 "longitude" => "-118.4065"
               }
             ]
           })
       }}
    )

    assert {:ok, location} = PostalCodeLookup.lookup(" us ", " 90210 ")
    assert location.latitude == 34.0901
    assert location.longitude == -118.4065
    assert location.place_name == "Beverly Hills"
    assert location.region == "California"
    assert location.country == "United States"

    assert_receive {:postal_lookup_request, url, headers, options}
    assert url == "https://api.zippopotam.us/US/90210"
    assert {"Accept", "application/json"} in headers
    assert options[:recv_timeout] == 5_000
  end

  test "returns not found for an unknown postal code" do
    respond_with({:ok, %HTTPoison.Response{status_code: 404, body: ""}})

    assert {:error, :not_found} = PostalCodeLookup.lookup("US", "00000")
  end

  test "rejects invalid country and postal code input without making a request" do
    assert {:error, :invalid_country_code} = PostalCodeLookup.lookup("USA", "90210")
    assert {:error, :invalid_postal_code} = PostalCodeLookup.lookup("US", "  ")
    refute_received {:postal_lookup_request, _, _, _}
  end

  test "rejects successful responses without usable coordinates" do
    respond_with(
      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: Jason.encode!(%{"places" => [%{"latitude" => "north", "longitude" => "west"}]})
       }}
    )

    assert {:error, :invalid_response} = PostalCodeLookup.lookup("US", "90210")
  end

  test "reports service and network failures as temporarily unavailable" do
    respond_with({:ok, %HTTPoison.Response{status_code: 503, body: "unavailable"}})
    assert {:error, :temporarily_unavailable} = PostalCodeLookup.lookup("US", "90210")

    respond_with({:error, %HTTPoison.Error{reason: :timeout}})
    assert {:error, :temporarily_unavailable} = PostalCodeLookup.lookup("US", "90210")
  end

  defp respond_with(response) do
    Application.put_env(:hueworks, :postal_code_http_response, response)
  end

  defp restore_env(key, nil), do: Application.delete_env(:hueworks, key)
  defp restore_env(key, value), do: Application.put_env(:hueworks, key, value)

  defmodule HttpClient do
    def get(url, headers, options) do
      send(self(), {:postal_lookup_request, url, headers, options})
      Application.fetch_env!(:hueworks, :postal_code_http_response)
    end
  end
end
