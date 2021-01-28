{
  programs = [
    "tna_bridged_md"
    "tna_dyn_hashing"
    "tna_meter_lpf_wred"
    "tna_port_metadata_extern"
    "tna_register"
    "tna_timestamp"
    "tna_checksum"
    ## Hangs
    #"tna_exact_match"
    "tna_mirror"
    "tna_ports"
    "tna_resubmit"
    "bri_with_pdfixed_thrift"
    "tna_32q_2pipe"
    "tna_counter"
    "tna_field_slice"
    "tna_multicast"
    "tna_proxy_hash"
    "tna_simple_switch"
    "tna_custom_hash"
    "tna_idletimeout"
    "tna_operations"
    "tna_pvs"
    "tna_snapshot"
    "tna_action_profile"
    "tna_digest"
    "tna_lpm_match"
    "tna_pktgen"
    "tna_random"
    "tna_symmetric_hash"
    "tna_action_selector"
    "tna_dkm"
    "tna_meter_bytecount_adjust"
    "tna_port_metadata"
    "tna_range_match"
    "tna_ternary_match"
    ## These require special build procedures, TBD
    # "p4rt_utests"
    # "bri_set_forwarding_pipeline"
    # "tna_32q_multiprogram"
  ];
  args = {
    tna_custom_hash = {
      pythonModules = [ "crcmod" ];
    };
    tna_proxy_hash = {
      pythonModules = [ "crcmod" ];
    };
  };
}
