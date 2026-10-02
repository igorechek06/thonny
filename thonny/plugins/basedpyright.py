import importlib.util
import os.path
import shutil
import subprocess
import sys
import typing
from logging import getLogger
from typing import Dict

from thonny import get_runner, get_workbench
from thonny.common import UserError
from thonny.lsp_proxy import LanguageServerProxy
from thonny.misc_utils import get_project_venv_interpreters
from thonny.running import create_frontend_python_process

logger = getLogger(__name__)


class BasedpyrightProxy(LanguageServerProxy):

    def get_settings(self) -> Dict:
        proxy = get_runner().get_backend_proxy()
        if proxy is None:
            return {}

        result = {
            "python": {},
            "basedpyright": {
                "analysis": {
                    "diagnosticMode": "openFilesOnly",
                    "diagnosticSeverityOverrides": {},
                    "logLevel": "Information",  # "Error", "Warning", "Information", "Trace"
                }
            },
        }

        project_path = get_workbench().get_local_project_path()
        logger.info("Detected project path: %s", project_path)
        if project_path is not None:
            base_path = project_path
        else:
            base_path = get_workbench().get_local_cwd()

        typings_path = os.path.join(base_path, "typings")

        if (
            proxy.interpreter_is_cpython_compatible()
            and proxy.has_local_interpreter()
            and proxy.get_target_executable()
        ):
            result["python"]["pythonPath"] = proxy.get_target_executable()
        elif project_path is not None:
            # may have a dev-venv in project directory
            venv_interpreters = get_project_venv_interpreters(project_path)
            if venv_interpreters:
                result["python"]["pythonPath"] = venv_interpreters[0]

        if not proxy.interpreter_is_cpython_compatible() or not proxy.has_local_interpreter():
            # MicroPython stdlib and frozen modules have only stubs, so the modules won't have source
            result["basedpyright"]["analysis"]["diagnosticSeverityOverrides"][
                "reportMissingModuleSource"
            ] = "none"

        user_stubs_path = proxy.get_user_stubs_location()
        # do not blindly set stubPath to a folder not (directly) containing stubs,
        # as this would unnecessarily hide the typings folder from Basedpyright
        if self._folder_may_contain_stubs_beyond_typeshed(user_stubs_path):
            result["basedpyright"]["analysis"]["stubPath"] = user_stubs_path
        if os.path.isdir(os.path.join(user_stubs_path, "stdlib")):
            result["basedpyright"]["analysis"]["typeshedPaths"] = [user_stubs_path]

        logger.info("Using following basedpyright configuration: %r", result)
        return result

    def _folder_may_contain_stubs_beyond_typeshed(self, path) -> bool:
        for name in os.listdir(path):
            if name not in [
                "bin",
                "board_definitions",
                "circuitpython_setboard",
                "stdlib",
                "stubs",
            ] and not name.endswith(".dist-info"):
                return True

        return False

    def _create_server_process(self) -> subprocess.Popen[bytes]:
        command = self._get_server_command()
        logger.info("basedpyright-langserver command: %r", command)

        if os.name == "nt":
            creationflags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startupinfo.wShowWindow = subprocess.SW_HIDE
        else:
            startupinfo = None
            creationflags = 0

        env = {
            key: os.environ[key]
            for key in os.environ
            if not key.startswith("PYTHON") and key != "VIRTUAL_ENV"
        }
        for key in env:
            logger.debug("Basedpyright env: %s=%r", key, env.get(key))

        return subprocess.Popen(
            command,
            executable=command[0],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            creationflags=creationflags,
            startupinfo=startupinfo,
            universal_newlines=False,
            env=env,
        )

    def _get_server_command(self) -> typing.List[str]:
        # Prefer basedpyright installed together with Thonny, as console scripts are not
        # available in bundles. Node is run directly, so that killing the server process
        # doesn't leave an orphaned node process behind.
        basedpyright_dir = self._find_package_dir("basedpyright")
        nodejs_dir = self._find_package_dir("nodejs_wheel")
        if basedpyright_dir is not None and nodejs_dir is not None:
            script_path = os.path.join(basedpyright_dir, "langserver.index.js")
            if os.name == "nt":
                node_path = os.path.join(nodejs_dir, "node.exe")
            else:
                node_path = os.path.join(nodejs_dir, "bin", "node")

            if os.path.isfile(script_path) and os.path.isfile(node_path):
                return [node_path, script_path, "--stdio"]

        server_path = shutil.which("basedpyright-langserver")
        if server_path is None:
            raise UserError("Can't find basedpyright-langserver")

        return [server_path, "--stdio"]

    def _find_package_dir(self, name: str) -> typing.Optional[str]:
        spec = importlib.util.find_spec(name)
        if spec is None or spec.origin is None:
            return None

        return os.path.dirname(spec.origin)

    def get_supported_language_ids(self) -> typing.Set[str]:
        return {"python"}


def load_plugin():
    get_workbench().add_language_server_proxy_class(BasedpyrightProxy)
