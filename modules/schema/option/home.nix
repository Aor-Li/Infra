{ lib, ... }:
{
  # User Configuration for Git
  den.schema.home.options = {
    fullname = lib.mkOption {
      type = lib.types.str;
      description = "Full name of the home's owner (used as git user.name).";
    };

    email = lib.mkOption {
      type = lib.types.str;
      description = "Email of the home's owner (used as git user.email).";
    };
  };
}
