defmodule PhoenixDemo.EndpointTest do
  use ExUnit.Case, async: false

  test "certification" do
    SiteEncrypt.Phoenix.Test.verify_certification(PhoenixDemo.Endpoint)
  end
end
