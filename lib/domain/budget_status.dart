enum BudgetLevel { ok, warning, over }

const warningRatio = 0.8;

BudgetLevel budgetLevel(int spentCents, int limitCents) {
  if (limitCents <= 0) return spentCents > 0 ? BudgetLevel.over : BudgetLevel.ok;
  if (spentCents >= limitCents) return BudgetLevel.over;
  if (spentCents >= limitCents * warningRatio) return BudgetLevel.warning;
  return BudgetLevel.ok;
}
