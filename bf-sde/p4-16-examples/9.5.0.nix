{
  programs = [
    "bri_handle"
    "bri_with_pdfixed_thrift"
    ## Requires a "custom config file", TBD
    # "tna_32q_2pipe"
    "tna_action_profile"
    "tna_action_selector"
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
    "tna_simple_switch"
    "tna_snapshot"
    "tna_symmetric_hash"
    "tna_ternary_match"
    "tna_timestamp"

    ## These require special build procedures, TBD
    # "p4rt_utests"
    # "bri_set_forwarding_pipeline"
    # "t2na_counter_true_egress_accounting"
    # "tna_32q_multiprogram"
  ];
  args = {
    default = {
      pythonModules = [ "ipaddress" ];
    };
    tna_custom_hash = {
      pythonModules = [ "crcmod" ];
    };
    tna_proxy_hash = {
      pythonModules = [ "crcmod" ];
    };
    bri_with_pdfixed_thrift = {
      pythonModules = [ "thrift" ];
    };
    tna_counter = {
      pythonModules = [ "thrift" ];
    };
  };
}
