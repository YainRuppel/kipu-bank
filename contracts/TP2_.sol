// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title KIPU-BANK
 * @author YAIN RUPPEL -TalentoTECH
 * @notice Bóvedas personales de ETH con: límite global de depósitos (limiteBanco) y
 *         tope por retiro por transacción (topeRetiroPorTx). Emite eventos,
 *         lleva contadores, usa errores personalizados y patrón CEI.
 * @dev CEI = Checks-Effects-Interactions. Las transferencias nativas usan `call`.
 */
contract KipuBank {
    /*//////////////////////////////////////////////////////////////
                               ERRORES
    //////////////////////////////////////////////////////////////*/

    /// @notice El monto provisto es cero (no tiene sentido operar con 0).
    error MontoCero();

    /// @notice Se excede el tope por transacción para retiros.
    /// @param solicitado Monto solicitado por el usuario.
    /// @param tope Límite máximo permitido por transacción.
    error RetiroSobreTope(uint256 solicitado, uint256 tope);

    /// @notice El usuario no tiene balance suficiente para retirar.
    /// @param solicitado Monto solicitado por el usuario.
    /// @param disponible Balance disponible en su bóveda.
    error BalanceInsuficiente(uint256 solicitado, uint256 disponible);

    /// @notice El depósito total superaría el límite global del banco.
    /// @param totalIntentado Nuevo total que se intentó alcanzar.
    /// @param limite Límite global configurado.
    error TopeBancoExcedido(uint256 totalIntentado, uint256 limite);

    /// @notice Falló el envío de ETH nativo.
    /// @param a Destinatario.
    /// @param monto Monto intentado.
    error TransferenciaNativaFallida(address a, uint256 monto);

    /*//////////////////////////////////////////////////////////////
                               EVENTOS
    //////////////////////////////////////////////////////////////*/

    /// @notice Se emite en cada depósito exitoso.
    /// @param usuario Dirección del depositante.
    /// @param monto Monto depositado (wei).
    /// @param balanceUsuario Nuevo balance del usuario.
    event Depositado(address indexed usuario, uint256 monto, uint256 balanceUsuario);

    /// @notice Se emite en cada retiro exitoso.
    /// @param usuario Dirección del retirante.
    /// @param monto Monto retirado (wei).
    /// @param balanceUsuario Nuevo balance del usuario.
    event Retirado(address indexed usuario, uint256 monto, uint256 balanceUsuario);

    /*//////////////////////////////////////////////////////////////
                           VARIABLES DE ESTADO
    //////////////////////////////////////////////////////////////*/

    /// @notice Límite global de depósitos (suma de todas las bóvedas).
    /// @dev Inmutable: se fija en el constructor.
    uint256 public immutable limiteBanco;

    /// @notice Tope máximo permitido por transacción de retiro.
    /// @dev Inmutable: se fija en el constructor.
    uint256 public immutable topeRetiroPorTx;

    /// @notice Cantidad total de depósitos realizados (métrica).
    uint256 public conteoDepositos;

    /// @notice Cantidad total de retiros realizados (métrica).
    uint256 public conteoRetiros;

    /// @notice Suma de todos los balances (para controlar el límite global).
    uint256 public saldoBancoTotal;

    /// @notice Bóveda personal por usuario: cuánto ETH tiene cada address.
    mapping(address => uint256) public boveda;

    /*//////////////////////////////////////////////////////////////
                              MODIFICADORES
    //////////////////////////////////////////////////////////////*/

    /// @notice Exige que el monto sea mayor a cero (reutilizable).
    /// @param monto Monto a validar.
    modifier noCero(uint256 monto) {
        if (monto == 0) revert MontoCero();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configura el límite global y el tope por retiro.
     * @param _limiteBanco Límite global de depósitos (wei).
     * @param _topeRetiroPorTx Tope por retiro (wei).
     */
    constructor(uint256 _limiteBanco, uint256 _topeRetiroPorTx) {
        // Validación explícita con errores personalizados
        if (_limiteBanco == 0) revert TopeBancoExcedido(0, 0);
        if (_topeRetiroPorTx == 0) revert RetiroSobreTope(0, 0);
        limiteBanco = _limiteBanco;
        topeRetiroPorTx = _topeRetiroPorTx;
    }

    /*//////////////////////////////////////////////////////////////
                           FUNCIONES PRINCIPALES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposita ETH en tu bóveda personal.
     * @dev CEI:
     *  - Checks: valida límites (monto > 0 y límite global).
     *  - Effects: actualiza estado (mapping/contadores).
     *  - Interactions: no hay llamadas externas aquí.
     */
    function depositar() external payable noCero(msg.value) {
        // CHECKS
        uint256 nuevoTotal = saldoBancoTotal + msg.value;
        if (nuevoTotal > limiteBanco) {
            revert TopeBancoExcedido(nuevoTotal, limiteBanco);
        }

        // EFFECTS
        boveda[msg.sender] += msg.value;
        saldoBancoTotal = nuevoTotal;
        unchecked {
            conteoDepositos++;
        }

        // INTERACTIONS: ninguna en depositar()
        emit Depositado(msg.sender, msg.value, boveda[msg.sender]);
    }

    /**
     * @notice Retira un monto de tu bóveda, respetando el tope por transacción.
     * @param monto Monto a retirar (wei).
     * @dev CEI: validaciones → actualizar estado → transferir al final.
     */
    function retirar(uint256 monto) external noCero(monto) {
        // CHECKS
        if (monto > topeRetiroPorTx) {
            revert RetiroSobreTope(monto, topeRetiroPorTx);
        }
        uint256 bal = boveda[msg.sender];
        if (monto > bal) {
            revert BalanceInsuficiente(monto, bal);
        }

        // EFFECTS
        unchecked {
            boveda[msg.sender] = bal - monto;
            saldoBancoTotal -= monto;
            conteoRetiros++;
        }

        // INTERACTIONS
        _transferenciaNativaSegura(payable(msg.sender), monto);

        emit Retirado(msg.sender, monto, boveda[msg.sender]);
    }

    /*//////////////////////////////////////////////////////////////
                         FUNCIONES DE LECTURA (VIEW)
    //////////////////////////////////////////////////////////////*/

    /// @notice Devuelve el balance de la bóveda del usuario.
    /// @param usuario Dirección a consultar.
    function saldoDe(address usuario) external view returns (uint256) {
        return boveda[usuario];
    }

    /// @notice Retorna métricas del contrato.
    /// @return _saldoBancoTotal Suma de todos los balances.
    /// @return _conteoDepositos Cantidad de depósitos.
    /// @return _conteoRetiros Cantidad de retiros.
    function estadisticas()
        external
        view
        returns (uint256 _saldoBancoTotal, uint256 _conteoDepositos, uint256 _conteoRetiros)
    {
        return (saldoBancoTotal, conteoDepositos, conteoRetiros);
    }

    /*//////////////////////////////////////////////////////////////
                         FUNCIONES PRIVADAS/INTERNAS
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfiere ETH de forma segura usando `call` y revierte si falla.
    /// @param a Destinatario.
    /// @param monto Monto (wei).
    function _transferenciaNativaSegura(address payable a, uint256 monto) private {
        (bool ok, ) = a.call{value: monto}("");
        if (!ok) revert TransferenciaNativaFallida(a, monto);
    }

    /*//////////////////////////////////////////////////////////////
                               RECEIVERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Bloquea envíos directos para forzar uso de `depositar()` y validar límites.
    receive() external payable {
        revert();
    }

    /// @notice Fallback bloqueado (evita llamadas no coincidentes).
    fallback() external payable {
        revert();
    }
}
