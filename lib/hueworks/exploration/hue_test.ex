# upstairs hue hub 192.168.1.162
# [{"success":{"username":"0GMTKdYDtkaPfKd6yS9hSOYek26dv-ChnDj4wohH"}}]

defmodule HueTest do
  @bridge_ip "192.168.1.162"
  @api_key "0GMTKdYDtkaPfKd6yS9hSOYek26dv-ChnDj4wohH"
  def list_lights() do
    url = "http://#{@bridge_ip}/api/#{@api_key}/lights"

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Jason.decode(body)

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "HTTP #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  def get_light(light_id) do
    url = "http://#{@bridge_ip}/api/#{@api_key}/lights/#{light_id}"

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Jason.decode(body)

      error ->
        {:error, error}
    end
  end

  def turn_on(light_id, brightness \\ 254) do
    url = "http://#{@bridge_ip}/api/#{@api_key}/lights/#{light_id}/state"
    body = Jason.encode!(%{on: true, bri: brightness})

    HTTPoison.put(url, body, [{"Content-Type", "application/json"}])
  end

  def turn_off(light_id) do
    url = "http://#{@bridge_ip}/api/#{@api_key}/lights/#{light_id}/state"
    body = Jason.encode!(%{on: false})

    HTTPoison.put(url, body, [{"Content-Type", "application/json"}])
  end

  def list_groups do
    url = "http://#{@bridge_ip}/api/#{@api_key}/groups"

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Jason.decode(body)

      error ->
        {:error, error}
    end
  end

  # def list_rooms do
  #   list_groups()
  #   |> Enum.filter()
  # end
end
