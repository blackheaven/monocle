(** metric.proto BuckleScript Encoding *)


(** {2 Protobuf JSON Encoding} *)

val encode_metric_info : MetricTypes.metric_info -> Js.Json.t Js.Dict.t
(** [encode_metric_info v dict] encodes [v] int the given JSON [dict] *)

val encode_list_request : MetricTypes.list_request -> Js.Json.t Js.Dict.t
(** [encode_list_request v dict] encodes [v] int the given JSON [dict] *)

val encode_list_response : MetricTypes.list_response -> Js.Json.t Js.Dict.t
(** [encode_list_response v dict] encodes [v] int the given JSON [dict] *)

val encode_trend : MetricTypes.trend -> Js.Json.t Js.Dict.t
(** [encode_trend v dict] encodes [v] int the given JSON [dict] *)

val encode_get_request_options : MetricTypes.get_request_options -> Js.Json.t Js.Dict.t
(** [encode_get_request_options v dict] encodes [v] int the given JSON [dict] *)

val encode_get_request : MetricTypes.get_request -> Js.Json.t Js.Dict.t
(** [encode_get_request v dict] encodes [v] int the given JSON [dict] *)

val encode_histo : MetricTypes.histo -> Js.Json.t Js.Dict.t
(** [encode_histo v dict] encodes [v] int the given JSON [dict] *)

val encode_histo_stat : MetricTypes.histo_stat -> Js.Json.t Js.Dict.t
(** [encode_histo_stat v dict] encodes [v] int the given JSON [dict] *)

val encode_get_response : MetricTypes.get_response -> Js.Json.t Js.Dict.t
(** [encode_get_response v dict] encodes [v] int the given JSON [dict] *)


(** {2 BS Decoding} *)

val decode_metric_info : Js.Json.t Js.Dict.t -> MetricTypes.metric_info
(** [decode_metric_info decoder] decodes a [metric_info] value from [decoder] *)

val decode_list_request : Js.Json.t Js.Dict.t -> MetricTypes.list_request
(** [decode_list_request decoder] decodes a [list_request] value from [decoder] *)

val decode_list_response : Js.Json.t Js.Dict.t -> MetricTypes.list_response
(** [decode_list_response decoder] decodes a [list_response] value from [decoder] *)

val decode_trend : Js.Json.t Js.Dict.t -> MetricTypes.trend
(** [decode_trend decoder] decodes a [trend] value from [decoder] *)

val decode_get_request_options : Js.Json.t Js.Dict.t -> MetricTypes.get_request_options
(** [decode_get_request_options decoder] decodes a [get_request_options] value from [decoder] *)

val decode_get_request : Js.Json.t Js.Dict.t -> MetricTypes.get_request
(** [decode_get_request decoder] decodes a [get_request] value from [decoder] *)

val decode_histo : Js.Json.t Js.Dict.t -> MetricTypes.histo
(** [decode_histo decoder] decodes a [histo] value from [decoder] *)

val decode_histo_stat : Js.Json.t Js.Dict.t -> MetricTypes.histo_stat
(** [decode_histo_stat decoder] decodes a [histo_stat] value from [decoder] *)

val decode_get_response : Js.Json.t Js.Dict.t -> MetricTypes.get_response
(** [decode_get_response decoder] decodes a [get_response] value from [decoder] *)
