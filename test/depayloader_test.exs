defmodule Membrane.Element.RTP.H264.DepayloaderTest do
  use ExUnit.Case
  use Bunch

  alias Membrane.Element.RTP.H264.{Depayloader, FU}
  alias Membrane.Support.Formatters.{FUFactory, STAPFactory, RBSPNaluFactory}
  alias Membrane.Buffer

  describe "Depayloader when processing data" do
    test "passes through packets with type 1..23 (RBSP types)" do
      data = RBSPNaluFactory.sample_nalu()
      buffer = %Buffer{payload: data}

      assert {{:ok, actions}, %{}} = Depayloader.handle_process(:input, buffer, nil, %{})
      assert {:output, result} = Keyword.fetch!(actions, :buffer)
      assert %Buffer{payload: <<1::32, processed_data::binary()>>} = result
      assert processed_data == data
    end

    test "parses FU-A packets" do
      assert {actions, state} =
               FUFactory.get_all_fixtures()
               |> Enum.map(&FUFactory.precede_with_fu_nal_header/1)
               ~> (enum -> Enum.zip(enum, 1..Enum.count(enum)))
               |> Enum.map(fn {elem, seq_num} ->
                 %Buffer{payload: elem, metadata: %{rtp: %{sequence_number: seq_num}}}
               end)
               |> Enum.reduce(%Depayloader.State{}, fn buffer, prev_state ->
                 Depayloader.handle_process(:input, buffer, nil, prev_state)
                 ~> (
                   {{:ok, redemand: :output}, %Depayloader.State{} = state} -> state
                   {{:ok, actions}, state} -> {actions, state}
                 )
               end)

      assert state == %Depayloader.State{}
      assert {:output, %Buffer{payload: data}} = Keyword.fetch!(actions, :buffer)
      assert data == <<1::32, FUFactory.glued_fixtures()::binary()>>
    end

    test "parses STAP-A packets" do
      data = STAPFactory.sample_data()
      buffer = %Buffer{payload: STAPFactory.into_stap_unit(data)}

      assert {{:ok, actions}, %{}} = Depayloader.handle_process(:input, buffer, nil, %{})

      actions
      |> Enum.zip(data)
      |> Enum.each(fn {result, original_data} ->
        assert {:buffer, {:output, %Buffer{payload: result_data}}} = result
        assert <<1::32, nalu_hdr::binary-size(1), ^original_data::binary>> = result_data
        assert nalu_hdr == STAPFactory.example_nalu_hdr()
      end)
    end
  end

  describe "Depayloader when handling events" do
    alias Membrane.Event.Discontinuity

    test "drops current accumulator in case of discontinuity" do
      result =
        Depayloader.handle_event(:input, %Discontinuity{}, nil, %Depayloader.State{pp_acc: %FU{}})

      assert {:ok, %Depayloader.State{}} == result
    end

    test "passes through rest of events" do
      assert {{:ok, actions}, state} =
               Depayloader.handle_event(:input, %Discontinuity{}, nil, %Depayloader.State{})

      assert actions == [forward: %Discontinuity{}]
      assert state == %Depayloader.State{}
    end
  end
end
