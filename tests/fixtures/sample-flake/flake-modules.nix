{ createFlakeModule, pub, mod, ... }:
pub mod "publicChild"
mod "privateChild"
createFlakeModule {
  rootVal = "root";
}
