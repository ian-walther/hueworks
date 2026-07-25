defmodule Hueworks.Location.PostalCodeLookup do
  @moduledoc false

  @base_url "https://api.zippopotam.us"
  @request_options [timeout: 3_000, recv_timeout: 5_000]

  def lookup(country_code, postal_code) do
    with {:ok, country_code} <- normalize_country_code(country_code),
         {:ok, postal_code} <- normalize_postal_code(postal_code),
         {:ok, response} <- request(country_code, postal_code),
         {:ok, payload} <- response_payload(response),
         {:ok, location} <- location_from_payload(payload) do
      {:ok, location}
    end
  end

  defp normalize_country_code(country_code) when is_binary(country_code) do
    country_code = country_code |> String.trim() |> String.upcase()

    if Regex.match?(~r/^[A-Z]{2}$/, country_code) do
      {:ok, country_code}
    else
      {:error, :invalid_country_code}
    end
  end

  defp normalize_country_code(_country_code), do: {:error, :invalid_country_code}

  defp normalize_postal_code(postal_code) when is_binary(postal_code) do
    postal_code = String.trim(postal_code)

    if postal_code != "" and String.length(postal_code) <= 20 do
      {:ok, postal_code}
    else
      {:error, :invalid_postal_code}
    end
  end

  defp normalize_postal_code(_postal_code), do: {:error, :invalid_postal_code}

  defp request(country_code, postal_code) do
    url = "#{@base_url}/#{URI.encode(country_code)}/#{URI.encode(postal_code)}"

    case http_client().get(url, [{"Accept", "application/json"}], @request_options) do
      {:ok, %HTTPoison.Response{} = response} -> {:ok, response}
      {:error, %HTTPoison.Error{}} -> {:error, :temporarily_unavailable}
      _other -> {:error, :temporarily_unavailable}
    end
  rescue
    _error -> {:error, :temporarily_unavailable}
  end

  defp response_payload(%HTTPoison.Response{status_code: 200, body: body}) do
    case Jason.decode(body) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      _other -> {:error, :invalid_response}
    end
  end

  defp response_payload(%HTTPoison.Response{status_code: 404}), do: {:error, :not_found}

  defp response_payload(%HTTPoison.Response{status_code: status}) when status >= 500,
    do: {:error, :temporarily_unavailable}

  defp response_payload(%HTTPoison.Response{}), do: {:error, :lookup_failed}

  defp location_from_payload(%{"places" => places} = payload) when is_list(places) do
    Enum.find_value(places, {:error, :invalid_response}, fn place ->
      with {:ok, latitude} <- coordinate(place["latitude"], -90.0, 90.0),
           {:ok, longitude} <- coordinate(place["longitude"], -180.0, 180.0) do
        {:ok,
         %{
           latitude: latitude,
           longitude: longitude,
           place_name: string_value(place["place name"]),
           region: string_value(place["state"]),
           country: string_value(payload["country"])
         }}
      else
        _error -> false
      end
    end)
  end

  defp location_from_payload(_payload), do: {:error, :invalid_response}

  defp coordinate(value, minimum, maximum) do
    with {:ok, value} <- number(value),
         true <- value >= minimum and value <= maximum do
      {:ok, value}
    else
      _error -> {:error, :invalid_coordinate}
    end
  end

  defp number(value) when is_number(value), do: {:ok, value * 1.0}

  defp number(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _other -> {:error, :invalid_number}
    end
  end

  defp number(_value), do: {:error, :invalid_number}

  defp string_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp string_value(_value), do: nil

  defp http_client do
    Application.get_env(:hueworks, :postal_code_http_client, HTTPoison)
  end
end
