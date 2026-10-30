module votacion::votacion;

use std::string::String;
use sui::event;
use sui::vec_set::{Self, VecSet};

// ===== Errores =====
const EVotantesVacio: u64 = 0;
const EVotantesRepetidos: u64 = 1;
const EVotanteNoAutorizado: u64 = 2;
const EYaVoto: u64 = 3;
const EVotacionCerrada: u64 = 4;
const ECapIncorrecta: u64 = 5;

// ===== Estados =====
const ABIERTA: u8 = 0;
const APROBADA: u8 = 1;
const RECHAZADA: u8 = 2;
const CANCELADA: u8 = 3;

// ===== Objetos =====

/// Objeto COMPARTIDO: cualquiera puede leerlo, pero solo votan los autorizados.
public struct Votacion has key {
    id: UID,
    titulo: String,
    votantes: VecSet<address>,
    ya_votaron: VecSet<address>,
    a_favor: u64,
    en_contra: u64,
    estado: u8,
}

/// Objeto PROPIO del creador. Solo tiene `key` (sin `store`),
/// asi que no se puede transferir fuera de este modulo.
public struct AdminCap has key {
    id: UID,
    votacion_id: ID,
}

// ===== Eventos =====
public struct VotacionCreada has copy, drop {
    votacion_id: ID,
    total_votantes: u64,
}

public struct VotoRegistrado has copy, drop {
    votacion_id: ID,
    votante: address,
    a_favor: bool,
}

public struct VotacionFinalizada has copy, drop {
    votacion_id: ID,
    estado: u8,
}

// ===== Funciones principales =====

/// Crea una votacion con una lista cerrada de votantes.
public fun crear(titulo: String, votantes: vector<address>, ctx: &mut TxContext) {
    assert!(!votantes.is_empty(), EVotantesVacio);

    let mut lista = vec_set::empty<address>();
    votantes.do!(|a| {
        assert!(!lista.contains(&a), EVotantesRepetidos);
        lista.insert(a);
    });
    let total = lista.length();

    let votacion = Votacion {
        id: object::new(ctx),
        titulo,
        votantes: lista,
        ya_votaron: vec_set::empty(),
        a_favor: 0,
        en_contra: 0,
        estado: ABIERTA,
    };
    let votacion_id = object::id(&votacion);

    let cap = AdminCap { id: object::new(ctx), votacion_id };

    event::emit(VotacionCreada { votacion_id, total_votantes: total });

    transfer::share_object(votacion);
    transfer::transfer(cap, ctx.sender());
}

/// Un voto por direccion autorizada. Se cierra sola al alcanzar la mayoria.
public fun votar(v: &mut Votacion, a_favor: bool, ctx: &TxContext) {
    assert!(v.estado == ABIERTA, EVotacionCerrada);

    let votante = ctx.sender();
    assert!(v.votantes.contains(&votante), EVotanteNoAutorizado);
    assert!(!v.ya_votaron.contains(&votante), EYaVoto);

    v.ya_votaron.insert(votante);
    if (a_favor) {
        v.a_favor = v.a_favor + 1;
    } else {
        v.en_contra = v.en_contra + 1;
    };

    event::emit(VotoRegistrado {
        votacion_id: object::id(v),
        votante,
        a_favor,
    });

    let mayoria = mayoria_requerida(v);
    if (v.a_favor >= mayoria) {
        v.estado = APROBADA;
        event::emit(VotacionFinalizada { votacion_id: object::id(v), estado: APROBADA });
    } else if (v.en_contra >= mayoria) {
        v.estado = RECHAZADA;
        event::emit(VotacionFinalizada { votacion_id: object::id(v), estado: RECHAZADA });
    };
}

/// Solo con el AdminCap de ESTA votacion y mientras siga abierta.
public fun cancelar(cap: &AdminCap, v: &mut Votacion) {
    assert!(cap.votacion_id == object::id(v), ECapIncorrecta);
    assert!(v.estado == ABIERTA, EVotacionCerrada);

    v.estado = CANCELADA;
    event::emit(VotacionFinalizada { votacion_id: object::id(v), estado: CANCELADA });
}

// ===== Consultas =====
public fun estado(v: &Votacion): u8 { v.estado }
public fun a_favor(v: &Votacion): u64 { v.a_favor }
public fun en_contra(v: &Votacion): u64 { v.en_contra }
public fun total_votantes(v: &Votacion): u64 { v.votantes.length() }
public fun total_votos(v: &Votacion): u64 { v.ya_votaron.length() }
public fun mayoria_requerida(v: &Votacion): u64 { v.votantes.length() / 2 + 1 }
public fun ya_voto(v: &Votacion, quien: address): bool { v.ya_votaron.contains(&quien) }

// Valores de los estados (para leerlos desde fuera del modulo)
public fun abierta(): u8 { ABIERTA }
public fun aprobada(): u8 { APROBADA }
public fun rechazada(): u8 { RECHAZADA }
public fun cancelada(): u8 { CANCELADA }

// ===== Ayudas solo para pruebas =====
#[test_only]
public fun cap_falso(votacion_id: ID, ctx: &mut TxContext): AdminCap {
    AdminCap { id: object::new(ctx), votacion_id }
}

#[test_only]
public fun destruir_cap(cap: AdminCap) {
    let AdminCap { id, votacion_id: _ } = cap;
    id.delete();
}
