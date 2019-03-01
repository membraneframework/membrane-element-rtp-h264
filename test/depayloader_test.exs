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
      state = %Depayloader.State{pp_acc: %FU{}}

      assert {:ok, %Depayloader.State{}} ==
               Depayloader.handle_event(:input, %Discontinuity{}, nil, state)
    end

    test "passes through rest of events" do
      assert {{:ok, actions}, state} =
               Depayloader.handle_event(:input, %Discontinuity{}, nil, %Depayloader.State{})

      assert actions == [forward: %Discontinuity{}]
      assert state == %Depayloader.State{}
    end
  end

  describe "Depayloader resets internal state in case of error and redemands" do
    test "when parsing Fragmentation Unit" do
      %Membrane.Buffer{
        metadata: %{rtp: %{sequence_number: 2}},
        payload:
          <<92, 1, 184, 105, 243, 121, 62, 233, 29, 109, 103, 237, 76, 39, 197, 20, 67, 149, 169,
            61, 178, 147, 249, 138, 15, 81, 60, 59, 234, 117, 32, 55, 245, 115, 49, 165, 19, 87,
            99, 15, 255, 51, 62, 243, 41, 9>>
      }
      ~> Depayloader.handle_process(:input, &1, nil, %Depayloader.State{pp_acc: %FU{}})
      |> assert_error_occurred()
    end

    test "when parsing Single Time Agregation Unit" do
      %Membrane.Buffer{
        metadata: %{rtp: %{sequence_number: 2}},
        payload: <<24>> <> <<35_402::16, 0, 0, 0, 0, 0, 0, 1, 1, 2>>
      }
      ~> Depayloader.handle_process(:input, &1, nil, %Depayloader.State{})
      |> assert_error_occurred()
    end

    test "when parsing not valid nalu" do
      %Membrane.Buffer{
        metadata: %{rtp: %{sequence_number: 2}},
        payload: <<128::8>>
      }
      ~> Depayloader.handle_process(:input, &1, nil, %Depayloader.State{})
      |> assert_error_occurred()
    end

    defp assert_error_occurred(result) do
      assert {{:ok, actions}, state} = result
      assert actions == [redemand: :output]
      assert state == %Depayloader.State{}
    end
  end
end
