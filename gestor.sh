#!/usr/bin/env bash

# =============================================================================
# This file is part of https://github.com/apuntes-uam-infomat/Apuntes
# Copyright (c) 2018 Manuel Blanc, Pablo Manso
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 3.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
# =============================================================================


## Si se sourcea este script, se instala como un alias con auto-completar
## Solo son distintos si se ejecuta `source gestor.sh`
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
	_gestor_cmd="$(basename ${BASH_SOURCE[0]%.sh})"
	alias "$_gestor_cmd"="$PWD/${BASH_SOURCE[0]}"

	## Funcion para generar el auto-completar
	_gestor() {
		local opts cur=$2 len="${#COMP_WORDS[@]}"
		COMPREPLY=()

		## No autocompletamos mas que 2 argumentos
		if [[ $len -gt 4 ]]; then return 0; fi

		## Autocompletado de nombres de comandos
		if [[ $len -lt 3 || ( $len -eq 3 && "${COMP_WORDS[1]}" == "ayuda" ) ]]; then
			local _gestor_path="$(alias "$_gestor_cmd" | cut -f2 -d\')"
			opts=$(perl -lane '
				next unless(/^#=/);
				$F[1] =~ s/_/-/g;
				printf "$F[1]\n";
				while (<> =~ /^#=/) {};
			' "$_gestor_path")
			COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
			return 0
		fi

		## Autocompletado de los nombres de asignaturas para algunos comandos
		if [[ $len -eq 3 ]]; then
			case "${COMP_WORDS[1]}" in
				compilar|empaquetar|limpiar)
					local IFS=$'\n'
					COMPREPLY=( $(compgen -d -X 'Cosas guays LaTeX' -X '.git' -- "$cur") )
					return 0
					;;
				*)
					return 0
					;;
			esac
		fi
	}
	complete -o filenames -o bashdefault -F _gestor gestor

	echo "alias $_gestor_cmd='$PWD/${BASH_SOURCE[0]}'"
	return 0
fi

# ===================================================================
# Utilidades

# Modo seguro y mejor globbing
set -eu -o pipefail
shopt -s extglob nullglob

# Navegamos al directorio donde este este script
cd "$( dirname "${BASH_SOURCE[0]}" )"

PACKAGE_DIR="$(pwd)/Cosas Guays LaTeX"
SILENT=false

# Formateo
F_RESET=$(tput sgr0)
F_BOLD=$(tput bold)
F_UNDER=$(tput smul)
F_RED=$(tput setaf 1)
F_GREEN=$(tput setaf 2)
F_YELLOW=$(tput setaf 3)
#F_BLUE=$(tput setaf 4)
#F_MAGENTA=$(tput setaf 5)
#F_CYAN=$(tput setaf 6)
#F_WHITE=$(tput setaf 7)

# Mini-comandos
INFO()  { "$SILENT" || echo >&2 "${F_BOLD}${F_GREEN}>>${F_RESET} $1"; }
WARN()  { "$SILENT" || echo >&2 "${F_BOLD}${F_YELLOW}>>${F_RESET} $1"; }
ERR()   { "$SILENT" || echo >&2 "${F_BOLD}${F_RED}>>${F_RESET} $1"; }
abort() { ERR "$1"; exit 1; }

# Seleccionador de asignatura
seleccionar_asignatura() {

	local asignatura="${1%%/}"

	# Comprobamos que tenga longitud no-nula
	[[ -n "$asignatura" ]] || abort "No se proporciono el nombre de la asignatura"

	# Comprobamos que exista el directorio
	[[ -d "$asignatura" ]] || abort "No existe un directorio '$asignatura/'"

	# Y que tenga al menos un .tex dentro!
	[[ -n "$(find "$asignatura" -maxdepth 1 -iname '*.tex')" ]] || abort "El directorio '$asignatura/' no contiene ningun fichero .tex"

	# Exito!
	echo "$asignatura"
	return 0
}

# ===================================================================
# Sub comandos

#= crear_asignatura @nombre [@abreviacion]
#= Crea la estructura de ficheros para una asignatura nueva.
cmdlet__crear_asignatura() {

	# Procesamos los argumentos
	# Si no hay abreviatura, usamos el nombre SIN los espacios
	local name="$1"
	local abbr="${2:-${name//[[:space:]]/}}"

	# Comprobamos que se haya proporcionado un nombre
	[[ -z "$name" ]] && abort "usage: $0 [name] [abbreviation]"

	# Sanity check: que no exista ya el directorio!
	[[ -e "$name" ]] && abort "Ya existe un fichero con el nombre $name!"

	INFO "Creando $name/ (abbrev: $abbr)"
	mkdir "$name" && cd "$name"

	local extra_tex_files_input="" subdir suffix

	# Creamos algunos directorios extra
	for subdir in img pdf tex pdf/tikzgen; do
		INFO "Creado directorio $name/$subdir (con fichero .keep)"
		mkdir -p "$subdir"
		touch "$subdir/.keep"
	done

	# Creamos fichero de ejercicios (antes era un bucle)
	suffix=Ejs

	texfile="tex/${abbr}_${suffix}.tex"
	printf -v extra_tex_files_input "%s\n\chapter{---}\n%s\n" "$extra_tex_files_input" "\input{$texfile}"
	echo "% -*- root: ../${abbr}.tex -*-" > "$texfile"
	INFO "Creado fichero extra $texfile"

	local current_year
	current_year=$(date +%y)
	local docdate

	# Primer o segundo cuatrimestre?
	if [[ $(date +%m ) -ge 8 ]]; then
		docdate="$current_year/$((current_year + 1)) C1"
	else
		docdate="$((current_year - 1))/$current_year C2"
	fi

	# Creamos el fichero base a partir de una plantilla
	cat > "$abbr.tex" <<-EOF
		\documentclass[palatino]{apuntes}

		\title{$name}
		\author{}
		\date{$docdate}

		% Paquetes adicionales

		% --------------------

		\begin{document}
		\pagestyle{plain}
		\maketitle

		\tableofcontents
		\newpage
		% Contenido.

		%% Apendices (ejercicios, examenes)
		\appendix
		$extra_tex_files_input
		\printindex
		\end{document}
	EOF


	INFO "Terminado con exito!"
}

#= compilar @asignatura
#= Compila los apuntes de la asignatura especificada.
cmdlet__compilar() {

	# Esta separado para no ignorar el codigo de retorno
	local asignatura;
	asignatura="$(seleccionar_asignatura "${1:-}")"

	INFO "Compilando ${F_UNDER}$asignatura${F_RESET} ..."

	# Preparamos para compilar...
	cd "$asignatura"
	mkdir -p pdf/tikzgen

	# Compilamos comprobando el codigo de retorno
	if ! latexmk -r "../latexmkrc.pl" > /dev/null; then

		ERR "Ha ocurrido un error fatal al compilar"
		ERR "Informacion de diagnostico en"
		ERR "    ${F_UNDER}$asignatura/$(echo pdf/*.log)${F_RESET}"
		ERR "Resuelva los errores, y vuelva a intentarlo"
		return 1

	fi

	INFO "Compilado con exito!"
	return 0
}

#= compilar_todo
#= Compila todos los apuntes.
cmdlet__compilar_todo() {

	local dir_num=0
	local dir_upd=0
	local dir_err=0

	while IFS= read -r -d $'\0' asignatura; do

		if ( cmdlet__compilar "$(dirname "$asignatura")" ); then
			(( dir_upd += 1 ))
		else
			(( dir_err += 1 ))
		fi

		(( dir_num += 1 ))

		INFO "================================================================"

	done < <( find . -mindepth 2 -maxdepth 2 -iname '*.tex' -print0 )

	INFO "Encontrado ${F_BOLD}$dir_num${F_RESET} asignaturas, de las cuales"
	INFO "    ${F_GREEN}$dir_upd${F_RESET} han sido compilados sin errores."
	INFO "    ${F_RED}$dir_err${F_RESET} han tenido algun problema."
	INFO ""
	INFO "Terminado ($(date))"

}

#= limpiar @asignatura
#= Limpia los apuntes de la asignatura especificada.
cmdlet__limpiar() {

	# Esta separado para no ignorar el codigo de retorno
	local asignatura;
	asignatura="$(seleccionar_asignatura "${1:-}")"

	INFO "Limpiando ${F_UNDER}$asignatura${F_RESET} ..."

	cd "$asignatura"
	latexmk -r "../latexmkrc.pl" -C
	cd ..
}

#= limpiar_todo
#= Limpia los archivos no necesarios de todos los directorios.
cmdlet__limpiar_todo() {

	local dir_num=0

	while IFS= read -r -d $'\0' asignatura; do

		limpiar "$(dirname "$asignatura")"
		(( dir_num += 1 ))

		INFO "================================================================"

	done < <( find . -mindepth 2 -maxdepth 2 -iname '*.tex' -print0 )

	INFO "Encontrado ${F_BOLD}$dir_num${F_RESET} asignaturas"
	INFO ""
	INFO "Terminado ($(date))"

}

#= empaquetar @asignatura
#= Empaqueta los ficheros de una asignatura en un zip.
cmdlet__empaquetar() {

	# Esta separado para no ignorar el codigo de retorno
	local asignatura;
	asignatura="$(seleccionar_asignatura "${1:-}")"

	# Zip de salida es la asignatura sin espacios
	local salida_zip="${asignatura//[[:space:]]/}.zip"

	# Variable con patrones a ignorar al empaquetar
	local tex_ignore="tikzaux"

	INFO "Empaquetando ${F_UNDER}$asignatura${F_RESET} ..."
	cd "$asignatura"

	if [[ -e "$salida_zip" ]]; then
		mv "$salida_zip" "$salida_zip.bak"
		WARN "Ya existe un archivo '$salida_zip'"
		WARN "Ha sido renombrado a '$salida_zip.bak'"
	fi

	zip "$salida_zip" !($tex_ignore).tex
	zip -r "$salida_zip" tex pdf tikz
	zip -j "$salida_zip" "$PACKAGE_DIR"/*.sty "$PACKAGE_DIR"/*.cls

	INFO "Empaquetado en '$asignatura/$salida_zip'"
	return 0
}

#= instalar
#= Instala localmente los paquetes de los apuntes.
cmdlet__instalar() {
	WARN "Esta funcionalidad no esta implementada aqui."
	WARN "Si realmente quieres instalar los paquetes globalmente,"
	WARN "ejecuta el script situado en ${F_UNDER}Cosas guays LaTeX/install${F_RESET}"
	return 0
}


#= ayuda [@cmd]
#= Muestra la ayuda de un comando, o de todos.
#= La informacion se extrae del propio fichero usando codigo Perl ilegible.
cmdlet__ayuda() {
	if ! type perl > /dev/null; then
		abort 'La ayuda usa perl. Abre el fichero directamente para ver los comentarios.'
	fi
	if [[ ${#@} -eq 0 ]]; then
		echo "uso: $F_BOLD$exe$F_RESET <comando> [<argumentos>]"
		echo ""
		echo "Los subcomandos validos son:"
		perl -lane '
			sub bold { `tput bold`.$_[0].`tput sgr0` }
			next unless (/^#=/); #next unless $. > 70;
			printf "   %-33s %s", (bold $F[1]), (<> =~ s/^#=\s+//r);
			while (<> =~ /^#=/) {};
		' "${BASH_SOURCE[0]}"
	else
		perl -wlane '
			$\="\n";
			sub under { `tput smul`.$_[0].`tput rmul` }
			sub bold  { `tput bold`.$_[0].`tput sgr0` }
			sub formatize {
				$_[0] =~ s/@([\w.-]+)/under $1/ge;
				$_[0] =~ s/((?:^|\s|(?<=\[))-[\w.-]+)/bold $1/ge;
				return $_[0];
			}
			next unless (/^#= \Q'$1'/);
			shift @F;
			$cmd = bold shift @F;
			chomp($des = ($_ = <>) =~ s/^#=\s+//r);
			print join " ", ("uso:", (bold "$cmd"), map { formatize $_ } @F);
			print "   $des";
			while (($_ = <>) =~ s/^#=\s+//) {
				chomp; next if /^$/; print "   ", formatize $_;
			}
			$found = 1;
			exit 0;
			END { print "Ayuda no encontrada para '$1'." unless $found; }
		' "${BASH_SOURCE[0]}"
	fi
}


# ===================================================================
# Seleccionador de utilidad

exe="$(basename "$0")"
cmd="cmdlet__${1//-/_}"

# Comprobamos que exista el subcomando como funcion
if [[ "$(type -t "$cmd")" != 'function' ]]; then
	abort "$exe: '$1' no es un comando valido. Vease '$0 ayuda'"
fi

# shift devuelve 1 (error) si no hay mas parametros posicionales
shift || true
"$cmd" "$@"
exit 0
