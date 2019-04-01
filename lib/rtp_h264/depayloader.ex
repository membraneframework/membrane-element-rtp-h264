defmodule Membrane.Element.RTP.H264.Depayloader do
  @moduledoc """
  Depayloads H264 RTP payloads into H264 NAL Units.
  """
  use Membrane.Element.Base.Filter
  use Membrane.Log

  alias Membrane.Buffer
  alias Membrane.Caps.{RTP, Video.H264}
  alias Membrane.Event.Discontinuity
  alias Membrane.Element.RTP.H264.{FU, NAL, StapA}

  @frame_prefix <<1::32>>
  @type sequence_number :: 0..65_535

  def_output_pads output: [
                    caps: {H264, stream_format: :byte_stream}
                  ]

  def_input_pads input: [
                   caps: {RTP, payload_type: :dynamic},
                   demand_unit: :buffers
                 ]

  defmodule State do
    @moduledoc false
    defstruct parser_acc: nil
  end

  def handle_init(_) do
    {:ok, %State{}}
  end

  @impl true
  def handle_caps(:input, _caps, _context, state) do
    {:ok, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload} = buffer, _ctx, state) do
    with {:ok, {header, _} = nal} <- NAL.Header.parse_unit_header(payload),
         unit_type = NAL.Header.decode_type(header),
         {{:ok, _actions}, _state} = action <- handle_unit_type(unit_type, nal, buffer, state) do
      action
    else
      {:error, reason} ->
        log_malformed_buffer(buffer, reason)
        {{:ok, redemand: :output}, %State{state | parser_acc: nil}}
    end
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state),
    do: {{:ok, demand: {:input, size}}, state}

  def handle_demand(:output, _, :bytes, _ctx, state), do: {{:error, :not_supported_unit}, state}

  @impl true
  def handle_event(:input, %Discontinuity{} = event, _context, %State{parser_acc: %FU{}} = state),
    do: {{:ok, forward: event}, %State{state | parser_acc: nil}}

  def handle_event(:input, event, _context, state), do: {{:ok, forward: event}, state}

  defp handle_unit_type(:single_nalu, _nal, buffer, state) do
    buffer_output(buffer.payload, buffer, state)
  end

  defp handle_unit_type(:fu_a, {header, data}, buffer, state) do
    %Buffer{metadata: %{rtp: %{sequence_number: seq_num}}} = buffer

    case FU.parse(data, seq_num, map_state_to_fu(state)) do
      {:ok, {data, type}} ->
        header = <<0::1, header.nal_ref_idc::2, type::5>>
        data = header <> data
        buffer_output(data, buffer, %State{state | parser_acc: nil})

      {:incomplete, fu} ->
        {{:ok, redemand: :output}, %State{state | parser_acc: fu}}

      {:error, _} = error ->
        error
    end
  end

  defp handle_unit_type(:stap_a, {_, data}, buffer, state) do
    with {:ok, result} <- StapA.parse(data) do
      buffers = Enum.map(result, &%Buffer{buffer | payload: add_prefix(&1)})
      {{:ok, buffer: {:output, buffers}}, state}
    end
  end

  defp buffer_output(data, buffer, state),
    do: {{:ok, action_from_data(data, buffer)}, state}

  defp action_from_data(data, buffer) do
    [buffer: {:output, %Buffer{buffer | payload: add_prefix(data)}}]
  end

  defp add_prefix(data), do: @frame_prefix <> data

  defp map_state_to_fu(%State{parser_acc: %FU{} = fu}), do: fu
  defp map_state_to_fu(_), do: %FU{}

  defp log_malformed_buffer(%Buffer{metadata: metadata}, reason) do
    %{rtp: %{sequence_number: seq_num}} = metadata

    warn("""
    An error occurred while parsing RTP frame with sequence_number: #{seq_num}
    Reason: #{reason}
    """)
  end
end