#[test_only]
module votacion::votacion_tests;

use sui::test_scenario as ts;
use votacion::votacion::{Self as vt, Votacion, AdminCap};

const ADMIN: address = @0xA;
const V1: address = @0x1;
const V2: address = @0x2;
const V3: address = @0x3;
const V4: address = @0x4;
const V5: address = @0x5;
const INTRUSO: address = @0xBAD;

// ----- Ayuda: crea una votacion con la lista dada y deja todo listo -----
fun crear_votacion(sc: &mut ts::Scenario, votantes: vector<address>) {
    vt::crear(b"Aprobar la propuesta".to_string(), votantes, sc.ctx());
    sc.next_tx(ADMIN);
}

// ----- Ayuda: un votante emite su voto -----
fun votar_como(sc: &mut ts::Scenario, quien: address, a_favor: bool) {
    sc.next_tx(quien);
    let mut v = sc.take_shared<Votacion>();
    vt::votar(&mut v, a_favor, sc.ctx());
    ts::return_shared(v);
}

// =====================  CREACION  =====================

#[test]
fun crear_con_tres_votantes() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3]);

    let v = sc.take_shared<Votacion>();
    assert!(vt::estado(&v) == vt::abierta());
    assert!(vt::total_votantes(&v) == 3);
    assert!(vt::mayoria_requerida(&v) == 2);
    assert!(vt::a_favor(&v) == 0 && vt::en_contra(&v) == 0);
    ts::return_shared(v);

    // El creador recibio su AdminCap
    let cap = sc.take_from_sender<AdminCap>();
    sc.return_to_sender(cap);
    sc.end();
}

#[test, expected_failure(abort_code = vt::EVotantesVacio)]
fun crear_sin_votantes_falla() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[]);
    sc.end();
}

#[test, expected_failure(abort_code = vt::EVotantesRepetidos)]
fun crear_con_votantes_repetidos_falla() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V1]);
    sc.end();
}

// =====================  VOTAR  =====================

#[test]
fun un_voto_valido_suma() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3]);

    votar_como(&mut sc, V1, true);

    sc.next_tx(ADMIN);
    let v = sc.take_shared<Votacion>();
    assert!(vt::a_favor(&v) == 1);
    assert!(vt::en_contra(&v) == 0);
    assert!(vt::ya_voto(&v, V1));
    assert!(!vt::ya_voto(&v, V2));
    assert!(vt::estado(&v) == vt::abierta()); // 1 voto no alcanza mayoria (2)
    ts::return_shared(v);
    let cap = sc.take_from_sender<AdminCap>();
    sc.return_to_sender(cap);
    sc.end();
}

#[test, expected_failure(abort_code = vt::EVotanteNoAutorizado)]
fun votante_no_autorizado_falla() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3]);
    votar_como(&mut sc, INTRUSO, true);
    sc.end();
}

#[test, expected_failure(abort_code = vt::EYaVoto)]
fun doble_voto_falla() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3]);
    votar_como(&mut sc, V1, true);
    votar_como(&mut sc, V1, false); // intenta votar otra vez
    sc.end();
}

// =====================  RESULTADOS  =====================

#[test]
fun dos_a_favor_aprueban() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3]);

    votar_como(&mut sc, V1, true);
    votar_como(&mut sc, V2, true);

    sc.next_tx(ADMIN);
    let v = sc.take_shared<Votacion>();
    assert!(vt::estado(&v) == vt::aprobada());
    assert!(vt::a_favor(&v) == 2);
    ts::return_shared(v);
    let cap = sc.take_from_sender<AdminCap>();
    sc.return_to_sender(cap);
    sc.end();
}

#[test]
fun dos_en_contra_rechazan() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3]);

    votar_como(&mut sc, V1, false);
    votar_como(&mut sc, V2, false);

    sc.next_tx(ADMIN);
    let v = sc.take_shared<Votacion>();
    assert!(vt::estado(&v) == vt::rechazada());
    ts::return_shared(v);
    let cap = sc.take_from_sender<AdminCap>();
    sc.return_to_sender(cap);
    sc.end();
}

#[test, expected_failure(abort_code = vt::EVotacionCerrada)]
fun no_se_vota_despues_de_la_mayoria() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3]);
    votar_como(&mut sc, V1, true);
    votar_como(&mut sc, V2, true); // aqui queda APROBADA
    votar_como(&mut sc, V3, false); // ya no se puede
    sc.end();
}

// Con cantidad IMPAR y todos votando siempre hay ganador (nunca empate).
#[test]
fun cinco_votantes_siempre_hay_mayoria() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3, V4, V5]);

    votar_como(&mut sc, V1, true);
    votar_como(&mut sc, V2, false);
    votar_como(&mut sc, V3, true);
    votar_como(&mut sc, V4, false);
    votar_como(&mut sc, V5, true); // 3 a favor, 2 en contra

    sc.next_tx(ADMIN);
    let v = sc.take_shared<Votacion>();
    assert!(vt::mayoria_requerida(&v) == 3);
    assert!(vt::estado(&v) == vt::aprobada());
    assert!(vt::a_favor(&v) == 3 && vt::en_contra(&v) == 2);
    ts::return_shared(v);
    let cap = sc.take_from_sender<AdminCap>();
    sc.return_to_sender(cap);
    sc.end();
}

// Con cantidad PAR puede haber empate y la votacion queda sin resultado.
// Por eso la demo se hace con cantidad impar de votantes.
#[test]
fun con_cantidad_par_puede_empatar() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3, V4]);

    votar_como(&mut sc, V1, true);
    votar_como(&mut sc, V2, true);
    votar_como(&mut sc, V3, false);
    votar_como(&mut sc, V4, false); // 2 a 2

    sc.next_tx(ADMIN);
    let v = sc.take_shared<Votacion>();
    assert!(vt::mayoria_requerida(&v) == 3);
    assert!(vt::estado(&v) == vt::abierta()); // nadie llego a 3
    ts::return_shared(v);
    let cap = sc.take_from_sender<AdminCap>();
    sc.return_to_sender(cap);
    sc.end();
}

// Invariante: los votos contados siempre coinciden con quienes ya votaron.
#[test]
fun los_votos_cuadran_con_los_votantes() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3, V4, V5]);

    votar_como(&mut sc, V1, true);
    votar_como(&mut sc, V2, false);

    sc.next_tx(ADMIN);
    let v = sc.take_shared<Votacion>();
    assert!(vt::a_favor(&v) + vt::en_contra(&v) == vt::total_votos(&v));
    assert!(vt::total_votos(&v) == 2);
    ts::return_shared(v);
    let cap = sc.take_from_sender<AdminCap>();
    sc.return_to_sender(cap);
    sc.end();
}

// =====================  CANCELAR  =====================

#[test]
fun cancelar_con_el_cap_correcto() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3]);

    let cap = sc.take_from_sender<AdminCap>();
    let mut v = sc.take_shared<Votacion>();
    vt::cancelar(&cap, &mut v);
    assert!(vt::estado(&v) == vt::cancelada());
    ts::return_shared(v);
    sc.return_to_sender(cap);
    sc.end();
}

#[test, expected_failure(abort_code = vt::ECapIncorrecta)]
fun cancelar_con_cap_de_otra_votacion_falla() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3]);

    let mut v = sc.take_shared<Votacion>();
    // Cap atado a OTRA votacion (otro ID)
    let falso = vt::cap_falso(object::id_from_address(@0xDEAD), sc.ctx());
    vt::cancelar(&falso, &mut v); // aborta aqui
    vt::destruir_cap(falso);
    ts::return_shared(v);
    sc.end();
}

#[test, expected_failure(abort_code = vt::EVotacionCerrada)]
fun no_se_cancela_una_votacion_ya_finalizada() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3]);
    votar_como(&mut sc, V1, true);
    votar_como(&mut sc, V2, true); // APROBADA

    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    let mut v = sc.take_shared<Votacion>();
    vt::cancelar(&cap, &mut v); // aborta aqui
    ts::return_shared(v);
    sc.return_to_sender(cap);
    sc.end();
}

// =====================  PRUEBAS ADICIONALES  =====================

// Una votacion cancelada no acepta votos.
#[test, expected_failure(abort_code = vt::EVotacionCerrada)]
fun no_se_vota_en_una_votacion_cancelada() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3]);

    let cap = sc.take_from_sender<AdminCap>();
    let mut v = sc.take_shared<Votacion>();
    vt::cancelar(&cap, &mut v);
    ts::return_shared(v);
    sc.return_to_sender(cap);

    votar_como(&mut sc, V1, true); // aborta aqui
    sc.end();
}

// No se puede cancelar dos veces la misma votacion.
#[test, expected_failure(abort_code = vt::EVotacionCerrada)]
fun no_se_cancela_dos_veces() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3]);

    let cap = sc.take_from_sender<AdminCap>();
    let mut v = sc.take_shared<Votacion>();
    vt::cancelar(&cap, &mut v);
    ts::return_shared(v);
    sc.return_to_sender(cap);

    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    let mut v = sc.take_shared<Votacion>();
    vt::cancelar(&cap, &mut v); // aborta aqui
    ts::return_shared(v);
    sc.return_to_sender(cap);
    sc.end();
}

// Cierre por RECHAZO con 5 votantes: 3 en contra y 2 a favor.
#[test]
fun cinco_votantes_rechazan_con_tres_en_contra() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1, V2, V3, V4, V5]);

    votar_como(&mut sc, V1, false);
    votar_como(&mut sc, V2, true);
    votar_como(&mut sc, V3, false);
    votar_como(&mut sc, V4, true);
    votar_como(&mut sc, V5, false); // 3 en contra, 2 a favor

    sc.next_tx(ADMIN);
    let v = sc.take_shared<Votacion>();
    assert!(vt::estado(&v) == vt::rechazada());
    assert!(vt::en_contra(&v) == 3 && vt::a_favor(&v) == 2);
    ts::return_shared(v);
    let cap = sc.take_from_sender<AdminCap>();
    sc.return_to_sender(cap);
    sc.end();
}

// Caso minimo: un solo votante decide (mayoria = 1).
#[test]
fun un_solo_votante_decide() {
    let mut sc = ts::begin(ADMIN);
    crear_votacion(&mut sc, vector[V1]);

    votar_como(&mut sc, V1, true);

    sc.next_tx(ADMIN);
    let v = sc.take_shared<Votacion>();
    assert!(vt::mayoria_requerida(&v) == 1);
    assert!(vt::estado(&v) == vt::aprobada());
    ts::return_shared(v);
    let cap = sc.take_from_sender<AdminCap>();
    sc.return_to_sender(cap);
    sc.end();
}
