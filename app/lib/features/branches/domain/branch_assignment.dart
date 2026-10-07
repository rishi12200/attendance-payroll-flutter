class BranchAssignment {
  const BranchAssignment({
    required this.primaryBranchId,
    required this.allowedBranchIds,
  });

  final String? primaryBranchId;
  final Set<String> allowedBranchIds;

  BranchAssignment selectPrimary(String? id) {
    final allowed = {...allowedBranchIds};
    if (id != null) allowed.add(id);
    return BranchAssignment(primaryBranchId: id, allowedBranchIds: allowed);
  }

  BranchAssignment toggleAllowed(String id, bool selected) {
    if (id == primaryBranchId && !selected) return this;
    final allowed = {...allowedBranchIds};
    if (selected) {
      allowed.add(id);
    } else {
      allowed.remove(id);
    }
    return BranchAssignment(
      primaryBranchId: primaryBranchId,
      allowedBranchIds: allowed,
    );
  }
}
