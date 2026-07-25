defmodule Hueworks.HomeAssistant.Authorization do
  @moduledoc false

  alias Hueworks.HomeAssistant.Host
  alias Hueworks.Schemas.Bridge.Credentials

  @callback_path "/config/bridges/home-assistant/callback"
  @request_timeout_ms 10_000

  def authorize(host, canonical_url, state)
      when is_binary(canonical_url) and is_binary(state) and state != "" do
    with {:ok, client_id} <- validate_callback_origin(canonical_url),
         {:ok, _base_url} <- Host.validate(host) do
      redirect_uri = "#{client_id}#{@callback_path}"

      query =
        URI.encode_query(%{
          "client_id" => client_id,
          "redirect_uri" => redirect_uri,
          "response_type" => "code",
          "state" => state
        })

      {:ok,
       %{
         client_id: client_id,
         redirect_uri: redirect_uri,
         url: "#{Host.http_url(host, "/auth/authorize")}?#{query}"
       }}
    else
      {:error, :invalid_host} -> {:error, :invalid_host}
      _ -> {:error, :invalid_callback_url}
    end
  end

  def authorize(_host, _canonical_url, _state), do: {:error, :invalid_callback_url}

  def exchange_code(host, client_id, code)
      when is_binary(client_id) and is_binary(code) and code != "" do
    fields = %{
      "client_id" => client_id,
      "code" => code,
      "grant_type" => "authorization_code"
    }

    with {:ok, payload} <- post_token(host, fields, :exchange),
         {:ok, credentials} <- exchange_credentials(payload, client_id) do
      {:ok, credentials}
    end
  end

  def exchange_code(_host, _client_id, _code), do: {:error, :authorization_failed}

  def refresh(host, %Credentials{} = credentials) do
    with true <- credentials.auth_type == "oauth",
         refresh_token when is_binary(refresh_token) and refresh_token != "" <-
           credentials.refresh_token,
         client_id when is_binary(client_id) and client_id != "" <- credentials.client_id,
         {:ok, payload} <-
           post_token(
             host,
             %{
               "client_id" => client_id,
               "grant_type" => "refresh_token",
               "refresh_token" => refresh_token
             },
             :refresh
           ),
         {:ok, refreshed} <- refresh_credentials(payload, credentials) do
      {:ok, refreshed}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :reauthorization_required}
    end
  end

  def refresh(_host, _credentials), do: {:error, :reauthorization_required}

  def callback_path, do: @callback_path

  defp validate_callback_origin(canonical_url) do
    uri = canonical_url |> String.trim() |> URI.parse()

    cond do
      uri.scheme not in ["http", "https"] ->
        {:error, :invalid_callback_url}

      not is_binary(uri.host) or uri.host in ["", "0.0.0.0", "::", "[::]"] ->
        {:error, :invalid_callback_url}

      uri.path not in [nil, "", "/"] or not is_nil(uri.query) or not is_nil(uri.fragment) ->
        {:error, :invalid_callback_url}

      true ->
        {:ok, canonical_origin(uri)}
    end
  end

  defp canonical_origin(uri) do
    uri
    |> Map.put(:path, nil)
    |> Map.put(:query, nil)
    |> Map.put(:fragment, nil)
    |> URI.to_string()
    |> String.trim_trailing("/")
  end

  defp post_token(host, fields, operation) do
    body = URI.encode_query(fields)
    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    case http_client().post(
           Host.http_url(host, "/auth/token"),
           body,
           headers,
           recv_timeout: @request_timeout_ms
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        decode_token_payload(response_body)

      {:ok, %HTTPoison.Response{status_code: status}}
      when operation == :refresh and status in [400, 401, 403] ->
        {:error, :reauthorization_required}

      {:ok, %HTTPoison.Response{status_code: status}} when status >= 500 ->
        {:error, :temporarily_unavailable}

      {:ok, %HTTPoison.Response{}} ->
        {:error, :authorization_failed}

      {:error, %HTTPoison.Error{}} ->
        {:error, :temporarily_unavailable}

      _ ->
        {:error, :authorization_failed}
    end
  rescue
    _error -> {:error, :temporarily_unavailable}
  end

  defp decode_token_payload(body) do
    case Jason.decode(body) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      _ -> {:error, :invalid_token_response}
    end
  end

  defp exchange_credentials(payload, client_id) do
    with {:ok, access_token, expires_in} <- access_token_fields(payload),
         refresh_token when is_binary(refresh_token) and refresh_token != "" <-
           payload["refresh_token"] do
      {:ok,
       oauth_credentials(
         access_token,
         refresh_token,
         expires_in,
         client_id
       )}
    else
      _ -> {:error, :invalid_token_response}
    end
  end

  defp refresh_credentials(payload, credentials) do
    with {:ok, access_token, expires_in} <- access_token_fields(payload) do
      {:ok,
       oauth_credentials(
         access_token,
         payload["refresh_token"] || credentials.refresh_token,
         expires_in,
         credentials.client_id
       )}
    end
  end

  defp access_token_fields(payload) do
    access_token = payload["access_token"]
    expires_in = payload["expires_in"]
    token_type = payload["token_type"]

    if is_binary(access_token) and access_token != "" and is_integer(expires_in) and
         expires_in > 0 and is_binary(token_type) and String.downcase(token_type) == "bearer" do
      {:ok, access_token, expires_in}
    else
      {:error, :invalid_token_response}
    end
  end

  defp oauth_credentials(access_token, refresh_token, expires_in, client_id) do
    %{
      "auth_type" => "oauth",
      "access_token" => access_token,
      "refresh_token" => refresh_token,
      "expires_at" => System.system_time(:second) + expires_in,
      "client_id" => client_id,
      "auth_status" => "ready"
    }
  end

  defp http_client do
    Application.get_env(:hueworks, :home_assistant_auth_http_client, HTTPoison)
  end
end
