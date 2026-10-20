# cbindgen 0.29.2: a Rust program Mesa's NVK (NVIDIA Vulkan driver) build runs. Mesa wants 0.28 or later.
# Offline: every crate in the program's Cargo.lock is a source, checked against the sha256 that Cargo.lock records.
name=cbindgen
version=0.29.2
release=1
description="Makes C headers from Rust code (what Mesa's NVK build needs)"
source=(
  cbindgen-0.29.2.tar.gz::https://static.crates.io/crates/cbindgen/cbindgen-0.29.2.crate
  anstream-0.6.19.crate::https://static.crates.io/crates/anstream/anstream-0.6.19.crate
  anstyle-1.0.11.crate::https://static.crates.io/crates/anstyle/anstyle-1.0.11.crate
  anstyle-parse-0.2.7.crate::https://static.crates.io/crates/anstyle-parse/anstyle-parse-0.2.7.crate
  anstyle-query-1.1.3.crate::https://static.crates.io/crates/anstyle-query/anstyle-query-1.1.3.crate
  anstyle-wincon-3.0.9.crate::https://static.crates.io/crates/anstyle-wincon/anstyle-wincon-3.0.9.crate
  autocfg-1.5.0.crate::https://static.crates.io/crates/autocfg/autocfg-1.5.0.crate
  bitflags-2.9.1.crate::https://static.crates.io/crates/bitflags/bitflags-2.9.1.crate
  cfg-if-1.0.1.crate::https://static.crates.io/crates/cfg-if/cfg-if-1.0.1.crate
  clap-4.5.41.crate::https://static.crates.io/crates/clap/clap-4.5.41.crate
  clap_builder-4.5.41.crate::https://static.crates.io/crates/clap_builder/clap_builder-4.5.41.crate
  clap_lex-0.7.5.crate::https://static.crates.io/crates/clap_lex/clap_lex-0.7.5.crate
  colorchoice-1.0.4.crate::https://static.crates.io/crates/colorchoice/colorchoice-1.0.4.crate
  dashmap-5.5.3.crate::https://static.crates.io/crates/dashmap/dashmap-5.5.3.crate
  diff-0.1.13.crate::https://static.crates.io/crates/diff/diff-0.1.13.crate
  equivalent-1.0.2.crate::https://static.crates.io/crates/equivalent/equivalent-1.0.2.crate
  errno-0.3.13.crate::https://static.crates.io/crates/errno/errno-0.3.13.crate
  fastrand-2.3.0.crate::https://static.crates.io/crates/fastrand/fastrand-2.3.0.crate
  getrandom-0.3.3.crate::https://static.crates.io/crates/getrandom/getrandom-0.3.3.crate
  hashbrown-0.14.5.crate::https://static.crates.io/crates/hashbrown/hashbrown-0.14.5.crate
  heck-0.5.0.crate::https://static.crates.io/crates/heck/heck-0.5.0.crate
  indexmap-2.5.0.crate::https://static.crates.io/crates/indexmap/indexmap-2.5.0.crate
  is_terminal_polyfill-1.70.1.crate::https://static.crates.io/crates/is_terminal_polyfill/is_terminal_polyfill-1.70.1.crate
  itoa-1.0.15.crate::https://static.crates.io/crates/itoa/itoa-1.0.15.crate
  lazy_static-1.5.0.crate::https://static.crates.io/crates/lazy_static/lazy_static-1.5.0.crate
  libc-0.2.174.crate::https://static.crates.io/crates/libc/libc-0.2.174.crate
  linux-raw-sys-0.9.4.crate::https://static.crates.io/crates/linux-raw-sys/linux-raw-sys-0.9.4.crate
  lock_api-0.4.13.crate::https://static.crates.io/crates/lock_api/lock_api-0.4.13.crate
  log-0.4.27.crate::https://static.crates.io/crates/log/log-0.4.27.crate
  memchr-2.7.5.crate::https://static.crates.io/crates/memchr/memchr-2.7.5.crate
  once_cell-1.21.3.crate::https://static.crates.io/crates/once_cell/once_cell-1.21.3.crate
  once_cell_polyfill-1.70.1.crate::https://static.crates.io/crates/once_cell_polyfill/once_cell_polyfill-1.70.1.crate
  parking_lot-0.12.4.crate::https://static.crates.io/crates/parking_lot/parking_lot-0.12.4.crate
  parking_lot_core-0.9.11.crate::https://static.crates.io/crates/parking_lot_core/parking_lot_core-0.9.11.crate
  pretty_assertions-1.4.1.crate::https://static.crates.io/crates/pretty_assertions/pretty_assertions-1.4.1.crate
  proc-macro2-1.0.95.crate::https://static.crates.io/crates/proc-macro2/proc-macro2-1.0.95.crate
  quote-1.0.40.crate::https://static.crates.io/crates/quote/quote-1.0.40.crate
  r-efi-5.3.0.crate::https://static.crates.io/crates/r-efi/r-efi-5.3.0.crate
  redox_syscall-0.5.13.crate::https://static.crates.io/crates/redox_syscall/redox_syscall-0.5.13.crate
  rustix-1.0.8.crate::https://static.crates.io/crates/rustix/rustix-1.0.8.crate
  ryu-1.0.20.crate::https://static.crates.io/crates/ryu/ryu-1.0.20.crate
  scopeguard-1.2.0.crate::https://static.crates.io/crates/scopeguard/scopeguard-1.2.0.crate
  serde-1.0.228.crate::https://static.crates.io/crates/serde/serde-1.0.228.crate
  serde_core-1.0.228.crate::https://static.crates.io/crates/serde_core/serde_core-1.0.228.crate
  serde_derive-1.0.228.crate::https://static.crates.io/crates/serde_derive/serde_derive-1.0.228.crate
  serde_json-1.0.140.crate::https://static.crates.io/crates/serde_json/serde_json-1.0.140.crate
  serde_spanned-1.0.0.crate::https://static.crates.io/crates/serde_spanned/serde_spanned-1.0.0.crate
  serial_test-2.0.0.crate::https://static.crates.io/crates/serial_test/serial_test-2.0.0.crate
  serial_test_derive-2.0.0.crate::https://static.crates.io/crates/serial_test_derive/serial_test_derive-2.0.0.crate
  smallvec-1.15.1.crate::https://static.crates.io/crates/smallvec/smallvec-1.15.1.crate
  strsim-0.11.1.crate::https://static.crates.io/crates/strsim/strsim-0.11.1.crate
  syn-2.0.104.crate::https://static.crates.io/crates/syn/syn-2.0.104.crate
  tempfile-3.20.0.crate::https://static.crates.io/crates/tempfile/tempfile-3.20.0.crate
  toml-0.9.2.crate::https://static.crates.io/crates/toml/toml-0.9.2.crate
  toml_datetime-0.7.0.crate::https://static.crates.io/crates/toml_datetime/toml_datetime-0.7.0.crate
  toml_parser-1.0.1.crate::https://static.crates.io/crates/toml_parser/toml_parser-1.0.1.crate
  toml_writer-1.0.2.crate::https://static.crates.io/crates/toml_writer/toml_writer-1.0.2.crate
  unicode-ident-1.0.18.crate::https://static.crates.io/crates/unicode-ident/unicode-ident-1.0.18.crate
  utf8parse-0.2.2.crate::https://static.crates.io/crates/utf8parse/utf8parse-0.2.2.crate
  wasi-0.14.2+wasi-0.2.4.crate::https://static.crates.io/crates/wasi/wasi-0.14.2+wasi-0.2.4.crate
  windows-sys-0.59.0.crate::https://static.crates.io/crates/windows-sys/windows-sys-0.59.0.crate
  windows-targets-0.52.6.crate::https://static.crates.io/crates/windows-targets/windows-targets-0.52.6.crate
  windows_aarch64_gnullvm-0.52.6.crate::https://static.crates.io/crates/windows_aarch64_gnullvm/windows_aarch64_gnullvm-0.52.6.crate
  windows_aarch64_msvc-0.52.6.crate::https://static.crates.io/crates/windows_aarch64_msvc/windows_aarch64_msvc-0.52.6.crate
  windows_i686_gnu-0.52.6.crate::https://static.crates.io/crates/windows_i686_gnu/windows_i686_gnu-0.52.6.crate
  windows_i686_gnullvm-0.52.6.crate::https://static.crates.io/crates/windows_i686_gnullvm/windows_i686_gnullvm-0.52.6.crate
  windows_i686_msvc-0.52.6.crate::https://static.crates.io/crates/windows_i686_msvc/windows_i686_msvc-0.52.6.crate
  windows_x86_64_gnu-0.52.6.crate::https://static.crates.io/crates/windows_x86_64_gnu/windows_x86_64_gnu-0.52.6.crate
  windows_x86_64_gnullvm-0.52.6.crate::https://static.crates.io/crates/windows_x86_64_gnullvm/windows_x86_64_gnullvm-0.52.6.crate
  windows_x86_64_msvc-0.52.6.crate::https://static.crates.io/crates/windows_x86_64_msvc/windows_x86_64_msvc-0.52.6.crate
  winnow-0.7.12.crate::https://static.crates.io/crates/winnow/winnow-0.7.12.crate
  wit-bindgen-rt-0.39.0.crate::https://static.crates.io/crates/wit-bindgen-rt/wit-bindgen-rt-0.39.0.crate
  yansi-1.0.1.crate::https://static.crates.io/crates/yansi/yansi-1.0.1.crate
)
checksums=(
  sha256:befbfd072a8e81c02f8c507aefce431fe5e7d051f83d48a23ffc9b9fe5a11799
  sha256:301af1932e46185686725e0fad2f8f2aa7da69dd70bf6ecc44d6b703844a3933
  sha256:862ed96ca487e809f1c8e5a8447f6ee2cf102f846893800b20cebdf541fc6bbd
  sha256:4e7644824f0aa2c7b9384579234ef10eb7efb6a0deb83f9630a49594dd9c15c2
  sha256:6c8bdeb6047d8983be085bab0ba1472e6dc604e7041dbf6fcd5e71523014fae9
  sha256:403f75924867bb1033c59fbf0797484329750cfbe3c4325cd33127941fabc882
  sha256:c08606f8c3cbf4ce6ec8e28fb0014a2c086708fe954eaa885384a6165172e7e8
  sha256:1b8e56985ec62d17e9c1001dc89c88ecd7dc08e47eba5ec7c29c7b5eeecde967
  sha256:9555578bc9e57714c812a1f84e4fc5b4d21fcb063490c624de019f7464c91268
  sha256:be92d32e80243a54711e5d7ce823c35c41c9d929dc4ab58e1276f625841aadf9
  sha256:707eab41e9622f9139419d573eca0900137718000c517d47da73045f54331c3d
  sha256:b94f61472cee1439c0b966b47e3aca9ae07e45d070759512cd390ea2bebc6675
  sha256:b05b61dc5112cbb17e4b6cd61790d9845d13888356391624cbe7e41efeac1e75
  sha256:978747c1d849a7d2ee5e8adc0159961c48fb7e5db2f06af6723b80123bb53856
  sha256:56254986775e3233ffa9c4d7d3faaf6d36a2c09d30b20687e9f88bc8bafc16c8
  sha256:877a4ace8713b0bcf2a4e7eec82529c029f1d0619886d18145fea96c3ffe5c0f
  sha256:778e2ac28f6c47af28e4907f13ffd1e1ddbd400980a9abd7c8df189bf578a5ad
  sha256:37909eebbb50d72f9059c3b6d82c0463f2ff062c9e95845c43a6c9c0355411be
  sha256:26145e563e54f2cadc477553f1ec5ee650b00862f0a58bcd12cbdc5f0ea2d2f4
  sha256:e5274423e17b7c9fc20b6e7e208532f9b19825d82dfd615708b70edd83df41f1
  sha256:2304e00983f87ffb38b55b444b5e3b60a884b5d30c0fca7d82fe33449bbe55ea
  sha256:68b900aa2f7301e21c36462b170ee99994de34dff39a4a6a528e80e7376d07e5
  sha256:7943c866cc5cd64cbc25b2e01621d07fa8eb2a1a23160ee81ce38704e97b8ecf
  sha256:4a5f13b858c8d314ee3e8f639011f7ccefe71f97f96e50151fb991f267928e2c
  sha256:bbd2bcb4c963f2ddae06a2efc7e9f3591312473c50c6685e1f298068316e66fe
  sha256:1171693293099992e19cddea4e8b849964e9846f4acee11b3948bcc337be8776
  sha256:cd945864f07fe9f5371a27ad7b52a172b4b499999f1d97574c9fa68373937e12
  sha256:96936507f153605bddfcda068dd804796c84324ed2510809e5b2a624c81da765
  sha256:13dc2df351e3202783a1fe0d44375f7295ffb4049267b0f3018346dc122a1d94
  sha256:32a282da65faaf38286cf3be983213fcf1d2e2a58700e808f83f4ea9a4804bc0
  sha256:42f5e15c9953c5e4ccceeb2e7382a716482c34515315f7b03532b8b4e8393d2d
  sha256:a4895175b425cb1f87721b59f0f286c2092bd4af812243672510e1ac53e2e0ad
  sha256:70d58bf43669b5795d1576d0641cfb6fbb2057bf629506267a92807158584a13
  sha256:bc838d2a56b5b1a6c25f55575dfc605fabb63bb2365f6c2353ef9159aa69e4a5
  sha256:3ae130e2f271fbc2ac3a40fb1d07180839cdbbe443c7a27e1e3c13c5cac0116d
  sha256:02b3e5e68a3a1a02aad3ec490a98007cbc13c37cbe84a3cd7b8e406d76e7f778
  sha256:1885c039570dc00dcb4ff087a89e185fd56bae234ddc7f056a945bf36467248d
  sha256:69cdb34c158ceb288df11e18b4bd39de994f6657d83847bdffdbd7f346754b0f
  sha256:0d04b7d0ee6b4a0207a0a7adb104d23ecb0b47d6beae7152d0fa34b692b29fd6
  sha256:11181fbabf243db407ef8df94a6ce0b2f9a733bd8be4ad02b4eda9602296cac8
  sha256:28d3b2b1366ec20994f1fd18c3c594f05c5dd4bc44d8bb0c1c632c8d6829481f
  sha256:94143f37725109f92c262ed2cf5e59bce7498c01bcc1502d7b9afe439a4e9f49
  sha256:9a8e94ea7f378bd32cbbd37198a4a91436180c5bb472411e48b5ec2e2124ae9e
  sha256:41d385c7d4ca58e59fc732af25c3983b67ac852c1a25000afe1175de458b67ad
  sha256:d540f220d3187173da220f885ab66608367b6574e925011a9353e4badda91d79
  sha256:20068b6e96dc6c9bd23e01df8827e6c7e1f2fddd43c21810382803c136b99373
  sha256:40734c41988f7306bb04f0ecf60ec0f3f1caa34290e4e8ea471dcd3346483b83
  sha256:0e56dd856803e253c8f298af3f4d7eb0ae5e23a737252cd90bb4f3b435033b2d
  sha256:91d129178576168c589c9ec973feedf7d3126c01ac2bf08795109aa35b69fb8f
  sha256:67b1b7a3b5fe4f1376887184045fcf45c69e92af734b7aaddc05fb777b6fbd03
  sha256:7da8b5736845d9f2fcb837ea5d9e2628564b3b043a70948a3f0b778838c5fb4f
  sha256:17b6f705963418cdb9927482fa304bc562ece2fdd4f616084c50b7023b435a40
  sha256:e8a64e3985349f2441a1a9ef0b853f869006c3855f2cda6862a94d26ebb9d6a1
  sha256:ed0aee96c12fa71097902e0bb061a5e1ebd766a6636bb605ba401c45c1650eac
  sha256:bade1c3e902f58d73d3f294cd7f20391c1cb2fbcb643b73566bc773971df91e3
  sha256:97200572db069e74c512a14117b296ba0a80a30123fbbb5aa1f4a348f639ca30
  sha256:fcc842091f2def52017664b53082ecbbeb5c7731092bad69d2c63050401dfd64
  sha256:5a5f39404a5da50712a4c1eecf25e90dd62b613502b7e925fd4e4d19b5c96512
  sha256:06abde3611657adf66d383f00b093d7faecc7fa57071cce2578660c9f1010821
  sha256:9683f9a5a998d873c0d21fcbe3c083009670149a8fab228644b8bd36b2c48cb3
  sha256:1e38bc4d79ed67fd075bcc251a1c39b32a1776bbe92e5bef1f0bf1f8c531853b
  sha256:9b724f72796e036ab90c1021d4780d4d3d648aca59e491e6b98e725b84e99973
  sha256:32a4622180e7a0ec044bb555404c800bc9fd9ec262ec147edd5989ccd0c02cd3
  sha256:09ec2a7bb152e2252b53fa7803150007879548bc709c039df7627cabbd05d469
  sha256:8e9b5ad5ab802e97eb8e295ac6720e509ee4c243f69d781394014ebfe8bbfa0b
  sha256:0eee52d38c090b3caa76c563b86c3a4bd71ef1a819287c19d586d7334ae8ed66
  sha256:240948bc05c5e7c6dabba28bf89d89ffce3e303022809e73deaefe4f6ec56c66
  sha256:147a5c80aabfbf0c7d901cb5895d1de30ef2907eb21fbbab29ca94c5b08b1a78
  sha256:24d5b23dc417412679681396f2b49f3de8c1473deb516bd34410872eff51ed0d
  sha256:589f6da84c646204747d1270a2a5661ea66ed1cced2631d546fdfb155959f9ec
  sha256:f3edebf492c8125044983378ecb5766203ad3b4c2f7a922bd7dd207f6d443e95
  sha256:6f42320e61fe2cfd34354ecb597f86f413484a798ba44a8ca1165c58d42da6c1
  sha256:cfe53a6657fd280eaa890a3bc59152892ffa3e30101319d168b781ed6529b049
)
depends=()
mode=staged

build() {
  # Cargo's directory source: each crate unpacked, with the checksum cargo wants (its list of files may be empty).
  mkdir -p vendor .cargo
  # (only the crates Cargo.lock names: /sources holds other packages' crates too)
  for base in $(awk '/^name = /{n=$3} /^version = /{v=$3} /^source = /{gsub(/"/,"",n); gsub(/"/,"",v); print n "-" v}' Cargo.lock); do
    crate=$srcdir/$base.crate
    tar -xf "$crate" -C vendor
    printf '{"files":{},"package":"%s"}' "$(sha256sum "$crate" | cut -d' ' -f1)" > "vendor/$base/.cargo-checksum.json"
  done
  cat > .cargo/config.toml <<CONFIG
[source.crates-io]
replace-with = "vendored"
[source.vendored]
directory = "$PWD/vendor"
CONFIG
  export CARGO_HOME=$PWD/.cargo-home
  cargo build --release --offline --locked
  install -Dm755 target/release/cbindgen "$DESTDIR/usr/bin/cbindgen"
}
