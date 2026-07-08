class ContractField<T> {
  const ContractField.absent() : isPresent = false, value = null;
  const ContractField.value(this.value) : isPresent = true;

  final bool isPresent;
  final T? value;
}
