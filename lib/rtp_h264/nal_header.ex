defmodule Membrane.Element.RTP.H264.NAL.Header do
  @moduledoc """
  Defines a structure representing Network Abstraction Layer Unit Header

  Defined in [RFC6184](https://tools.ietf.org/html/rfc6184#section-5.3)

  ```
    +---------------+
    |0|1|2|3|4|5|6|7|
    +-+-+-+-+-+-+-+-+
    |F|NRI|  Type   |
    +---------------+
  ```
  """

  @typedoc """
  NRI stands for nal_ref_idc. This value represents importance of
  frame that is being parsed.

  The higher the value the more important frame is (for example key
  frames have nri value of 3) and a value of 00 indicates that the
  content of the NAL unit is not used to reconstruct reference pictures
  for inter picture prediction. NAL units with NRI equal 0 can be discarded
  without risking the integrity of the reference pictures, although these
  payloads might contain metadata.
  """
  @type nri :: 0..3

  @typedoc """
  Specifies the type of RBSP data structure contained in the NAL unit.

    Types are defined as follows.

  | ID       | RBSP Type      |
  |----------|----------------|
  | 0        | Unspecified    |
  | 1-23     | NAL unit types |
  | 24       | STAP-A         |
  | 25       | STAP-B         |
  | 26       | MTAP-16        |
  | 27       | MTAP-24        |
  | 28       | FU-A           |
  | 29       | FU-B           |
  | Reserved | 30-31          |

  RBSP stands for Raw Byte Sequence Payload

  RBSP types are described in detail [here](https://yumichan.net/video-processing/video-compression/introduction-to-h264-nal-unit)
  """
  @type type :: 1..31

  @type supported_types :: :stap_a | :fu_a
  @type unsupported_types :: :stap_b | :mtap_16 | :mtap_24 | :fu_b
  @type types :: :single_nalu | supported_types | unsupported_types | :reserved

  defstruct [:nal_ref_idc, :type]

  @type t :: %__MODULE__{
          nal_ref_idc: nri(),
          type: type()
        }

  @spec parse_unit_header(binary()) :: {:error, :malformed_data} | {:ok, {t(), binary()}}
  def parse_unit_header(raw_nal)

  def parse_unit_header(<<0::1, nri::2, type::5, rest::binary()>>) do
    nal = %__MODULE__{
      nal_ref_idc: nri,
      type: type
    }

    {:ok, {nal, rest}}
  end

  # If first bit is not set to 0 packet is flagged as malformed
  def parse_unit_header(_), do: {:error, :malformed_data}

  @doc """
  Parses type stored in NAL Header
  """
  @spec decode_type(t) :: types()
  def decode_type(%__MODULE__{type: type}), do: do_decode_type(type)

  defp do_decode_type(number) when number in 1..21, do: :single_nalu
  defp do_decode_type(24), do: :stap_a
  defp do_decode_type(25), do: :stap_b
  defp do_decode_type(26), do: :mtap_16
  defp do_decode_type(27), do: :mtap_24
  defp do_decode_type(28), do: :fu_a
  defp do_decode_type(29), do: :fu_b
  defp do_decode_type(number) when number in 30..31 or number in [22, 23], do: :reserved
end
