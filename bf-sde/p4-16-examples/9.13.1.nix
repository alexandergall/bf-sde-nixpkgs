{ pkgs, platform}:

{
  programs = [
    ## Takes too long to complete
    # "bri_grpc_error"
    "bri_handle"
    "bri_with_pdfixed_thrift"
    ## Requires a "custom config file", TBD
    # "tna_32q_2pipe"
    ## Very extensive test
    #"selector_resize"
    "tna_action_profile"
    "tna_action_selector"
    "tna_alpm"
    "tna_bridged_md"
    "tna_checksum"
    "tna_counter"
    "tna_custom_hash"
    "tna_digest"
    "tna_dkm"
    "tna_dyn_hashing"
    ## Takes too long to complete
    # "tna_exact_match"
    "tna_field_slice"
    "tna_idletimeout"
    "tna_lpm_match"
    "tna_meter_bytecount_adjust"
    "tna_meter_lpf_wred"
    "tna_mirror"
    "tna_multicast"
    "tna_operations"
    "tna_pktgen"
    "tna_port_metadata"
    "tna_port_metadata_extern"
    "tna_ports"
    "tna_proxy_hash"
    "tna_pvs"
    "tna_random"
    "tna_range_match"
    "tna_register"
    "tna_resubmit"
    "tna_snapshot"
    "tna_symmetric_hash"
    "tna_ternary_match"
    "tna_timestamp"

    ## These require special build procedures, TBD
    # "p4rt_utests"
    # "bri_set_forwarding_pipeline"
    # "tna_32q_multiprogram"
  ] ++ pkgs.lib.optionals (platform == "modelT2") [
    "t2na_counter_true_egress_accounting"
    ## Requires a special build procedures, TBD
    # "t2na_counter_true_egress_accounting"
  ];
  args = {
    tna_custom_hash = {
      pythonModules = [ "crcmod" ];
    };
    tna_proxy_hash = {
      pythonModules = [ "crcmod" ];
    };
    tna_dyn_hashing = {
      pythonModules = [ "crcmod" ];
    };
    tna_counter = {
      pythonModules = [ "thrift" ];
    };
    tna_multicast = {
      pythonModules = [ "thrift" ];
    };
    bri_with_pdfixed_thrift = {
      pythonModules = [ "thrift" ];
    };
  } // pkgs.lib.optionalAttrs (platform == "modelT2") {
    t2na_counter_true_egress_accounting = {
      ptfPkgs = with pkgs; [ iproute2 ];
    };
  };
}
