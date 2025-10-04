# kipu-bank

Instrucciones de despliegue (Remix + Sepolia)

Abrí Remix y crea contracts/KipuBank.sol. Pega el contrato BancoKipu.
Pestaña Solidity Compiler
Versión: 0.8.26
Compilar.
Pestaña Deploy & Run Transactions
Envronment: Injected Provider – MetaMask (esto conecta Remix con MetaMask).

Contract: BancoKipu
  Constructor (valores en wei):
  limiteBanco: por ejemplo 5 ether → 5000000000000000000  
topeRetiroPorTx: por ejemplo 0.5 ether → 500000000000000000
Value: 0 (no enviar ETH al desplegar).
Gas limit: 5000000 (sugerido).
Deploy → Confirmar en MetaMask.
Copiá la dirección del contrato (aparece en “Deployed Contracts”).
  
Ejemplo: 0xABC...123
Notas importantes
  Wei = entero (no usar 0.5 con decimales); 1 ether = 10^18 wei.
 
