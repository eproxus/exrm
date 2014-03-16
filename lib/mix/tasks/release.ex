defmodule Mix.Tasks.Release do
  @moduledoc """
  Build a release for the current mix application.

  ## Examples

    # Build a release using defaults
    mix release
    # Use a specific version of ERTS
    mix release --erts=6.0
    # Use a specific version of Elixir (branch or tag name)
    mix release --elixir=v0.13
    # Pass args to erlexec when running the release
    mix release --erl="-env TZ UTC"
    # Set the verbosity level
    mix release --verbosity=[silent|quiet|normal|verbose]

  You may pass any number of arguments as needed. Make sure you pass arguments
  using `--key=value`, not `--key value`, as the args may be interpreted incorrectly
  otherwise.

  """
  @shortdoc "Build a release for the current mix application."

  use    Mix.Task
  import ExRM.Release.Utils

  @_RELXCONF "relx.config"
  @_RUNNER   "runner"
  @_NAME     "{{{PROJECT_NAME}}}"
  @_VERSION  "{{{PROJECT_VERSION}}}"
  @_ERTS_VSN "{{{ERTS_VERSION}}}"
  @_ERL_OPTS "{{{ERL_OPTS}}}"

  def run(args) do
    # Ensure this isn't an umbrella project
    if Mix.Project.umbrella? do
      raise Mix.Error, message: "Umbrella projects are not currently supported!"
    end
    # Collect release configuration
    config = [ priv_path:  Path.join([__DIR__, "..", "..", "..", "priv"]) |> Path.expand,
               name:       Mix.project |> Keyword.get(:app) |> atom_to_binary,
               version:    Mix.project |> Keyword.get(:version),
               erts:       "6.0",
               erl:        "",
               verbosity:  :quiet]
    config
    |> Keyword.merge(args |> parse_args)
    |> prepare_elixir
    |> prepare_relx
    |> build_project
    |> generate_relx_config
    |> generate_runner
    |> do_release

    info "Your release is ready!"
  end

  defp prepare_elixir(config) do
    # Ensure Elixir has been cloned, and the right branch is checked out
    config |> Keyword.get(:elixir, :default) |> fetch_elixir
    # Ensure Elixir is built
    case build_elixir do
      :ok ->
        # Continue...
        config
      {:error, message} ->
        error message
        exit(:normal)
    end
  end

  defp prepare_relx(config) do
    # Ensure relx has been downloaded
    case fetch_relx do
      :ok ->
        # Continue...
        config
      {:error, message} ->
        error message
        exit(:normal)
    end
  end

  defp build_project(config) do
    # Fetch deps, and compile, using the prepared Elixir binaries
    mix "deps.get",     :prod
    mix "deps.compile", :prod
    mix "compile",      :prod
    # Continue...
    config
  end

  defp generate_relx_config(config) do
    priv    = config |> Keyword.get(:priv_path)
    name    = config |> Keyword.get(:name)
    version = config |> Keyword.get(:version)
    source  = Path.join([priv, "rel", @_RELXCONF])
    base    = Path.join(File.cwd!, "rel")
    dest    = Path.join(base, @_RELXCONF)
    # Ensure destination base path exists
    File.mkdir_p!(base)
    contents = File.read!(source) 
      |> String.replace(@_NAME, name)
      |> String.replace(@_VERSION, version)
    File.write!(dest, contents)
    # Return the project config after we're done
    config
  end

  defp generate_runner(config) do
    priv     = config |> Keyword.get(:priv_path)
    name     = config |> Keyword.get(:name)
    version  = config |> Keyword.get(:version)
    erts     = config |> Keyword.get(:erts)
    erl_opts = config |> Keyword.get(:erl)
    source   = Path.join([priv, "rel", "files", @_RUNNER])
    base     = Path.join([File.cwd!, "rel", "files"])
    dest     = Path.join(base, @_RUNNER)
    # Ensure destination base path exists
    File.mkdir_p!(base)
    debug "Generating boot script..."
    contents = File.read!(source)
      |> String.replace(@_NAME, name)
      |> String.replace(@_VERSION, version)
      |> String.replace(@_ERTS_VSN, erts)
      |> String.replace(@_ERL_OPTS, erl_opts)
    File.write!(dest, contents)
    # Make executable
    dest |> chmod("+x")
    # Return the project config after we're done
    config
  end

  defp do_release(config) do
    debug "Generating release..."
    name      = config |> Keyword.get(:name)
    version   = config |> Keyword.get(:version)
    verbosity = config |> Keyword.get(:verbosity)
    # Do release
    case relx name, version, verbosity do
      :ok ->
        # Clean up template files
        Mix.Tasks.Release.Clean.do_cleanup(:relfiles)
        # Continue..
        config
      {:error, message} ->
        error message
        exit(:normal)
    end
  end

  defp parse_args(argv) do
    {args, _, _} = OptionParser.parse(argv)
    args |> Enum.map(&parse_arg/1)
  end
  defp parse_arg({:verbosity, verbosity}), do: {:verbosity, binary_to_atom(verbosity)}
  defp parse_arg({_key, _value} = arg),    do: arg

end
