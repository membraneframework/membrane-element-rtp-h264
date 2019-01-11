defmodule Membrane.Element.RTP.H264.StapATest do
  use ExUnit.Case
  use Bunch

  alias Membrane.Element.RTP.H264.StapA

  describe "Parser" do
    test "properly decodes nal agregate" do
      test_data = gen_test_data()

      {:ok, result} =
        test_data
        |> StapFactory.binaries_into_stap()
        |> StapA.parse()

      Enum.zip(result, test_data)
      |> Enum.each(fn {<<_nalu_hdr::8, a::binary>>, b} ->
        assert a == b
      end)
    end

    test "returns error when packet is malformed" do
      assert {:error, :packet_malformed} == StapA.parse(<<35402::16, 0, 0, 0, 0, 0, 0, 1, 1, 2>>)
    end
  end

  defp gen_test_data() do
    1..10
    |> Enum.map(&<<&1::8>>)
  end
end
