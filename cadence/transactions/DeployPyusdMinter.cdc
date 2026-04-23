transaction(code: String) {
    prepare(signer: auth(AddContract) &Account) {
        signer.contracts.add(name: "PyusdMinter", code: code.utf8)
    }
}
